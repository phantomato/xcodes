require 'bundler/inline'
require 'optparse'
require 'json'
require 'english'

gemfile do
  source 'https://rubygems.org'
  gem 'octokit'
end

# Define a variable to hold the semver component to bump
component = nil
formula = nil
token = nil
# Initialize an instance of OptionParser

options = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options]"

  opts.on('-c', '--component COMPONENT', 'Semver component to bump (major, minor, patch)') do |c|
    component = c
  end

  opts.on('-f', '--formula FORMULA', 'formula name') do |f|
    formula = f
  end

  opts.on('-t', '--token TOKEN', 'Github token') do |t|
    token = t
  end

  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end

# Parse the command line arguments
options.parse!

# If no arguments were provided, print the help message
if [component, formula].any?(&:nil?)
  puts options
  exit
end

class Semver
  attr_accessor :major, :minor, :patch

  def initialize(version: '0.0.0')
    @major, @minor, @patch = version.split('.').map(&:to_i)
    raise 'Invalid version format' if [@major, @minor, @patch].any?(&:nil?)
  end

  def bump_major
    @major += 1
    @minor = 0
    @patch = 0
    self
  end

  def bump_minor
    @minor += 1
    @patch = 0
    self
  end

  def bump_patch
    @patch += 1
    self
  end

  def self.latest
    latest_tag = `git describe --abbrev=0 --tags`.strip
    if latest_tag.match?(/\d+\.\d+\.\d+/)
      new(version: latest_tag)
    else
      new
    end
  end

  def to_s
    "#{@major}.#{@minor}.#{@patch}"
  end
end

def run_commands(action: '')
  print "#{action}..."
  value = yield
  puts 'OK.'
  value
end

next_version = Semver.latest
case component
when 'major'
  next_version.bump_major
when 'minor'
  next_version.bump_minor
when 'patch'
  next_version.bump_patch
else
  raise 'Invalid component'
end

puts "Bumping #{component} to version #{next_version}."

hash, file_name = run_commands(action: 'Buildig release') do
  `make bottle VERSION=#{next_version}`.lines.last.chomp.split
end

def repo_info
  repo_url = `git remote get-url origin`.chomp

  # Parse the owner and repo name from the URL
  if repo_url.start_with?('git@github.com:')
    # SSH format
    owner, repo = repo_url.match(%r{git@github\.com:(.*)/(.*)\.git}).captures
  elsif repo_url.start_with?('https://github.com/')
    # HTTPS format
    owner, repo = repo_url.match(%r{https://github\.com/(.*)/(.*)\.git}).captures
  else
    raise 'Unsupported repository URL format'
  end

  { owner:, repo: }
end

client = Octokit::Client.new(access_token: token)
repo = client.repository(repo_info)
raise 'Repository not found' unless repo

asset_url = run_commands(action: 'Creating a new release') do
  release = client.create_release(
    repo.id,
    next_version,
    {
      target_commitish: 'main',
      name: next_version,
      body: "Release #{next_version}",
      draft: true
    }
  )

  asset = client.upload_asset(release.url, file_name, { content_type: 'application/x-zip' })
  asset.browser_download_url
end

formula_info = `brew info --json -q #{formula}`.chomp
raise 'Formula info not found' unless $CHILD_STATUS.exitstatus.zero?

formula_info_json = JSON.parse(formula_info).first

run_commands(action: "Adding tap #{formula_info_json['tap']}") do
  `brew tap #{formula_info_json['tap']} -q`
end

current_tap = run_commands(action: "Getting tap's local path") do
  installed_taps = `brew tap-info --installed --json`.chomp
  taps_json = JSON.parse(installed_taps)
  taps_json.find { |tap| tap['name'] == formula_info_json['tap'] }
end

Dir.chdir(current_tap['path']) do
  run_commands(action: 'Cleaning tap artifacts') do
    `git reset --hard`
    `git clean -fd`
    `git pull`
  end

  run_commands(action: 'Bumping the formula') do
    `brew bump-formula-pr -q --write-only --commit --no-audit --no-fork --url #{asset_url} --sha256 #{hash} #{formula}`
  end
end

puts 'Done.'
