require "crawling/version"
require "diffy"
require "pathname"

module Crawling
  # path to repository for user(s)
  HOME_PARENT_DIR = 'home'

  # path to repository for the system
  SYSTEM_PARENT_DIR = 'system'

  N_LINES_DIFF_CONTEXT = 3

  def self.child_files_recursive path
    Dir.glob("#{path}/**/*", File::FNM_DOTMATCH).reject(&File.method(:directory?))
  end

  # relative_to must be an absolute Pathname
  def self.relative_path_to target, relative_to
    Pathname.new(target).expand_path.relative_path_from relative_to
  end

  # Like File.cp but also creates the parent directory at destination if it doesn't exist
  def self.copy_file src_file, dest_file
    dest_parent_dir = File.dirname dest_file
    FileUtils.mkdir_p dest_parent_dir unless Dir.exist? dest_parent_dir
    begin
      FileUtils.cp(src_file, dest_file)
    rescue
      raise "could not copy from #{src_file} to #{dest_file}"
    end
  end

  class Store
    attr_reader :store_dir

    def initialize store_dir, sys_dir
      @store_dir = File.absolute_path store_dir
      @store_pathname = Pathname.new(store_dir).expand_path
      @sys_dir = File.absolute_path sys_dir
      @sys_pathname = Pathname.new(sys_dir).expand_path
    end

    # if path is within store then return system path otherwise return nil
    def get_sys_path path
      if path.start_with? @store_dir
        File.join @sys_dir, Crawling.relative_path_to(path, @store_pathname)
      end
    end

    # if path is within system then return store path otherwise return nil
    def get_store_path path
      if path.start_with? @sys_dir
        File.join @store_dir, Crawling.relative_path_to(path, @sys_pathname)
      end
    end
  end

  class Instance
    def initialize(config_dir: nil, home_dir: nil, merge_app: nil)
      @home_dir = home_dir || ENV['HOME']
      @config_dir = config_dir || "#{@home_dir}/.config/crawling"
      @config_pathname = Pathname.new(@config_dir).expand_path
      @merge_app = merge_app || 'vimdiff %s %h'

      stores = { 'home' => @home_dir }
      @stores = stores.map do |store_dir, sys_dir|
        store_dir = File.join(@config_dir, store_dir)
        Store.new store_dir, sys_dir
      end
    end

    def cd
      FileUtils::mkdir_p @config_dir unless Dir.exists? @config_dir
      Dir.chdir @config_dir
      puts "creating shell in #{@config_dir}, type exit or ctrl-D to exit"
      system ENV['SHELL']
      puts "crawling shell exited"
    end

    def add paths
      raise "add command requires paths" if paths.empty?

      paths.each do |path|
        raise "path #{path} does not exist" unless File.exists? path

        each_with_storage_path(files_from path) do |file, storage_file|
          Crawling.copy_file file, storage_file
        end
      end
    end

    def get paths
      raise "get command requires paths" if paths.empty?

      each_with_storage_path(paths) do |path, storage_path|
        raise "path #{path} does not exist in storage" unless File.exists? storage_path

        files_from(storage_path).each do |storage_file|
          if storage_file == storage_path
            Crawling.copy_file storage_file, path
          else
            # path was a directory so recalculate new system path
            path_offset = storage_file[storage_path.length..-1]
            Crawling.copy_file storage_file, path + path_offset
          end
        end
      end
    end

    def diff paths = nil
      each_with_storage_path(files_from_paths_or_all paths) do |file, storage_file|
        missing_from = file_or_storage_file_doesnt_exist file, storage_file
        if missing_from
          puts "#{file}: doesn't exist in #{missing_from}"
          next
        end

        diff = get_diff storage_file, file
        unless diff == ''
          puts "#{file}:"
          puts diff
          puts
        end
      end
    end

    def merge paths = nil
      each_with_storage_path(files_from_paths_or_all paths) do |file, storage_file|
        missing_from = file_or_storage_file_doesnt_exist file, storage_file
        if missing_from
          case missing_from
          when 'system'
            puts "#{file}: creating in system from store"
            Crawling.copy_file storage_file, file
          when 'store'
            puts "#{file}: creating in store from system"
            Crawling.copy_file file, storage_file
          else
            puts "#{file}: does not exist in system or store"
          end

          next
        end

        while (diff_string = get_diff storage_file, file) != ''
          print "#{file}: [a]dd to store, [g]et from store, [d]iff, [m]erge, [s]kip? "
          answer = STDIN.gets.chomp
          case answer
          when 'a'
            Crawling.copy_file file, storage_file
            break
          when 'g'
            Crawling.copy_file storage_file, file
            break
          when 'd'
            puts diff_string
            puts
            redo
          when 'm'
            system *@merge_app.sub('%s', storage_file).sub('%h', file).split(' ')
          when 's'
            break
          else
            puts 'please answer with a, d, g, m, or s'
            redo
          end
        end
      end
    end

    def clone
      raise "clone: command not supported yet"
    end

    private
    def get_config_dir
      @config_dir
    end

    def each_with_storage_path paths
      paths.each do |path|
        pair = get_path_pair(path)
        raise "could not resolve #{path} to store" if pair.nil?
        yield pair
      end
    end

    def get_path_pair path
      path = File.absolute_path path
      @stores.each do |store|
        sys_path = store.get_sys_path path
        return [ sys_path, path ] if sys_path
        store_path = store.get_store_path path
        return [ path, store_path ] if store_path
      end
      nil
    end

    # if paths is empty then get all paths from stores otherwise get files
    # recursively reachable from the provided paths
    def files_from_paths_or_all paths
      if paths.nil?
        @stores.map { |store| Crawling.child_files_recursive(store.store_dir) }.flatten
      else
        paths.map(&method(:files_from)).flatten
      end
    end

    def files_from path
      Dir.exists?(path) ? Crawling.child_files_recursive(path) : [path]
    end

    def file_or_storage_file_doesnt_exist file, storage_file
      if not File.exists? file
        if File.exists? storage_file
          'system'
        else
          'system directory or store'
        end
      elsif not File.exists? storage_file
        'store'
      end
    end

    def get_diff src_file, dest_file
      diff = Diffy::Diff.new(
        src_file,
        dest_file,
        source: 'files',
        include_diff_info: true,
        context: N_LINES_DIFF_CONTEXT
      ).to_s
    end
  end
end
