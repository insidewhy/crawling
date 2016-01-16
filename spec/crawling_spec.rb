require 'spec_helper'
require 'fileutils'

describe Crawling do
  TEST_DIR = 'test'
  PROJECT_ROOT = File.dirname(File.dirname(__FILE__))
  CONFIG_DIR = File.join PROJECT_ROOT, TEST_DIR, 'tmp'
  CRAWLING = File.join PROJECT_ROOT, 'bin', 'crawling'

  before(:each) do
    FileUtils.rm_r CONFIG_DIR if Dir.exists? CONFIG_DIR
    @config_dir = CONFIG_DIR
    @output_dir = CONFIG_DIR
    @starting_dir = Dir.pwd
  end

  after(:each) do
    Dir.chdir @starting_dir
  end

  def run_crawling *args
    system CRAWLING, '-c', @config_dir, *args
  end

  def head path
    File.open path, 'r' do |file|
      return file.readline.chomp
    end
  end

  def files_should_exist parent_dir, *files
    expected_data_files = files.map do |file|
      data_path = File.join(parent_dir, file)
      expect(head data_path).to eql(file)
      expect(File).to exist(data_path)
      data_path
    end

    data_files = Crawling.child_files_recursive parent_dir
    extra_files = data_files - expected_data_files
    expect(extra_files).to be_empty, lambda { "unexpected files in #{parent_dir}: #{extra_files}" }
  end

  def data_files_should_exist parent_dir, *files
    files_should_exist File.join(@output_dir, parent_dir), *files
  end

  # at last... i see land!
  it 'has a version number' do
    expect(Crawling::VERSION).not_to be nil
  end

  it 'adds a directory and a file better' do
    config_dir = '/tmp'
    crawling = Crawling::Instance.new(home_dir: '.', config_dir: config_dir)
    expect(Dir).to receive(:exists?).with('dir') { true }
    expect(Dir).to receive(:exists?).with('file1') { false }
    expect(Crawling).to receive(:child_files_recursive).with('dir') { ['dir/file1'] }
    expect(Crawling).to receive(:copy_file).with('dir/file1', File.join(config_dir, 'home', 'dir/file1'))
    expect(Crawling).to receive(:copy_file).with('file1', File.join(config_dir, 'home', 'file1'))
    allow(File).to receive(:exists?) { true }
    crawling.add(['dir', 'file1'])
  end

  it 'adds a single file within the subdirectory specified with an absolute path' do
    home_dir = File.join(TEST_DIR, 'home1')
    run_crawling '-H', home_dir, 'add', File.absolute_path(File.join(home_dir, 'dir', 'file2'))
    data_files_should_exist 'home', 'dir/file2'
  end

  it 'gets a directory and a file' do
    @config_dir = File.join(@output_dir, 'config')
    @output_dir = File.join(@output_dir, 'username')
    home_dir = @output_dir

    FileUtils.mkdir_p @config_dir
    FileUtils.cp_r File.join(TEST_DIR, 'home1'), File.join(@config_dir, 'home')
    FileUtils.mkdir_p @output_dir

    Dir.chdir File.join(home_dir)
    run_crawling '-H', '.', 'get', 'file1', 'dir/subdir'

    files_should_exist '.', 'file1', 'dir/subdir/file1'
  end
end
