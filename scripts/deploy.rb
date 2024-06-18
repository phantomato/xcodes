require 'bundler/inline'
require 'optparse'
require 'json'

gemfile do
  source 'https://rubygems.org'
end

# Define a variable to hold the semver component to bump
component = nil
formula = nil
# Initialize an instance of OptionParser
options = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options]"

  opts.on("-c", "--component COMPONENT", "Semver component to bump (major, minor, patch)") do |c|
    component = c
  end

  opts.on("-f", "--formula FORMULA", "formula name") do |f|
    formula = f
  end

  opts.on("-h", "--help", "Displays Help") do
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

  def initialize(version: "0.0.0")
    @major, @minor, @patch = version.split('.').map(&:to_i)
    raise "Invalid version format" if [@major, @minor, @patch].any?(&:nil?)
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

next_version = Semver.latest
case component
when "major"
  next_version.bump_major
when "minor"
  next_version.bump_minor
when "patch"
  next_version.bump_patch
else
  raise "Invalid component"
end

puts "Bumping #{component} to version #{next_version}."

formula_info = `brew info --json -q #{formula}`.chomp
raise "Formula info not found" unless $?.exitstatus == 0
formula_info_json = JSON.parse(formula_info).first

print "Adding tap #{formula_info_json["tap"]}..."
`brew tap #{formula_info_json["tap"]} -q`
puts "OK."

print "Getting tap's local path..."
installed_taps = `brew tap-info --installed --json`.chomp
taps_json = JSON.parse(installed_taps)
current_tap = taps_json.find { |tap| tap["name"] == formula_info_json["tap"] }
puts "OK."

Dir.chdir(current_tap["path"]) do
end


puts "Done."