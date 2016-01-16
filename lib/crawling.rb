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

  class Instance
    def initialize(config_dir: nil, home_dir: nil, merge_app: nil)
      @home_dir = home_dir || ENV['HOME']
      @home_pathname = Pathname.new(@home_dir).expand_path
      @config_dir = config_dir || "#{@home_dir}/.config/crawling"
      @config_pathname = Pathname.new(@config_dir).expand_path
      @merge_app = merge_app || 'vimdiff %s %h'
    end

    def cd(subdir = nil)
      cd_dir = get_config_dir
      cd_dir = Path.join(cd_dir, subdir) if subdir
      raise "directory #{subdir} doesn't exist" unless Dir.exists? cd_dir

      Dir.chdir cd_dir
      puts "creating shell in #{cd_dir}, type exit or ctrl-D to exit"
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
          sys_path = from_storage_path storage_file
          Crawling.copy_file storage_file, sys_path
        end
      end
    end

    def diff paths
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

    def merge paths
      each_with_storage_path(files_from_paths_or_all paths) do |file, storage_file|
        missing_from = file_or_storage_file_doesnt_exist file, storage_file
        if missing_from
          case missing_from
          when 'home'
            puts "#{file}: creating from store"
            Crawling.copy_file storage_file, file
          when 'store'
            puts "#{file}: creating in store from home"
            Crawling.copy_file storage_file, file
          else
            puts "#{file}: does not exist in home or store"
          end

          next
        end

        while (diff_string = get_diff storage_file, file) != ''
          print "#{file}: show [d]iff, [m]erge, take [h]ome, take [S]tore, skip [n]ext? "
          answer = STDIN.gets.chomp
          case answer
          when 'd'
            puts diff_string
            puts
            redo
          when 'h'
            Crawling.copy_file file, storage_file
            break
          when 'm'
            system *@merge_app.sub('%s', storage_file).sub('%h', file).split(' ')
          when 'n'
            break
          when 'S'
            Crawling.copy_file storage_file, file
            break
          else
            puts 'please answer with d, h, m, n or S'
            redo
          end
        end
      end
    end

    def git_clone origin
      raise "must supply git repository" if origin.nil?
      puts "TODO: git clone #{origin}"
    end

    private
    def get_config_dir
      FileUtils::mkdir_p @config_dir unless Dir.exists? @config_dir
      @config_dir
    end

    def relative_path_to target, relative_to
      Pathname.new(target).expand_path.relative_path_from relative_to
    end

    def each_with_storage_path paths
      paths.each do |path|
        yield path, get_storage_path(path)
      end
    end

    def get_home_path path
      relative_path_to path, @home_pathname
    end

    def get_storage_path path
      # TODO: get system or home path depending on whether it is a subdirectory of the current user
      File.join @config_dir, HOME_PARENT_DIR, get_home_path(path)
    end

    def from_storage_path path
      cfg_rel_path = Pathname.new(relative_path_to path, @config_pathname)
      head, *tail = Pathname(cfg_rel_path).each_filename.to_a
      if head === 'home'
        File.join @home_dir, *tail
      else
        raise "storage type #{head} not supported yet"
      end
    end

    # if paths is empty then get home paths for all paths in storage, else get the
    # files recursively reachable from the provided paths
    def files_from_paths_or_all paths
      if paths.empty?
        # TODO: also support 'SYSTEM_PARENT_DIR'
        Crawling.child_files_recursive(
          File.join(@config_dir, HOME_PARENT_DIR)
        ).map &method(:from_storage_path)
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
          'home'
        else
          'home directory or store'
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
