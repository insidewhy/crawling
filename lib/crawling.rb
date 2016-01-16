require "crawling/version"
require "diffy"
require "pathname"

module Crawling
  # path to repository for user(s)
  HOME_PARENT_DIR = 'home'

  # path to repository for the system
  SYSTEM_PARENT_DIR = 'system'

  def self.child_files_recursive path
    Dir.glob("#{path}/**/*").reject(&File.method(:directory?))
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
    def initialize(config_dir: nil, home_dir: nil)
      @home_dir = home_dir || ENV['HOME']
      @home_pathname = Pathname.new(@home_dir).expand_path
      @config_dir = config_dir || "#{@home_dir}/.config/crawling"
      @config_pathname = Pathname.new(@config_dir).expand_path
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

        files_from(path).each do |file|
          storage_file = get_storage_path file
          Crawling.copy_file file, storage_file
        end
      end
    end

    def get paths
      raise "get command requires paths" if paths.empty?

      paths.each do |path|
        storage_path = get_storage_path path
        raise "path #{path} does not exist in storage" unless File.exists? storage_path

        files_from(storage_path).each do |storage_file|
          sys_path = from_storage_path storage_file
          Crawling.copy_file storage_file, sys_path
        end
      end
    end

    def diff paths
      if paths.empty?
        # TODO: get all path offsets from data directory
      end
      puts "TODO: diff #{paths}"
    end

    def merge paths
      if paths.empty?
        # TODO: get all path offsets from data directory
      end
      puts "TODO: merge #{paths}"
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

    def files_from path
      Dir.exists?(path) ? Crawling.child_files_recursive(path) : [path]
    end
  end
end
