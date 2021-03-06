#!/usr/bin/env ruby

require "fileutils"
require "tempfile"

#this scripts helps migrate my plugin tests from test::unit to rspec

#see: http://www.devchix.com/2008/01/04/migrating-from-testunit-to-rspec/
def prepare_file_and_directories(test_unit_dir, rspec_dir)
  puts "dir: #{test_unit_dir.path} -> #{rspec_dir.path}"
  test_unit_dir.each do |file|
    unless file == "." or file == ".."
      full_file = File.join(test_unit_dir.path, file)
      if File.directory? full_file
        spec_file = full_file.gsub(/test/, "spec")
        spec_file.gsub!(/unit/, "models")
        spec_file.gsub!(/functional/, "controllers")
        FileUtils.mkdir_p(spec_file) unless File.exists? spec_file
        prepare_file_and_directories(Dir.new(full_file), Dir.new(spec_file))
      else
        new_spec = File.join(rspec_dir.path, file.gsub(/_test/, "_spec").gsub("test_helper", "spec_helper"))
        puts "  file: #{full_file} -> #{new_spec}"
        FileUtils.copy(full_file, new_spec)
      end
    end
  end
end

def convert_test_unit_file_to_rspec(file)
  puts "convert: #{file}"
  tmp = Tempfile.new(File.basename(file))
  modules_to_include = nil
  begin
    lines = File.readlines(file)
    render_views = lines.any?{|l|l.match /assert_tag|response.body|assert_select/} && !lines.any?{|l|l.match /IntegrationTest/}
    lines.each do |line|
      line.chomp!
      line.gsub!(/\s+$/, "")
      indentation = line.scan(/^(\s*)/)[0][0]
      if line =~ %r[^(\s*#.*)$] #comments
        tmp.puts $1
      elsif line =~ %r[require.*?test_helper]
        if !file.match /spec_helper/
          if $should_keep_spec_helper
            tmp.puts line.gsub("test_helper", "spec_helper")
          else
            tmp.puts %(require "spec_helper")
          end
          if lines.any?{|l| l.match /assert_(no_)?difference/}
            tmp.puts %[require "active_support/testing/assertions"]
            modules_to_include = "include ActiveSupport::Testing::Assertions"
          end
        else
          tmp.puts %[require File.expand_path("../../../redmine_base_rspec/spec/spec_helper", __FILE__)]
        end
      elsif (line !~ %r[Controller] && line =~ %r[class\s+(.+?)Test < .+TestCase]) || line =~ %r[class\s*(.*?)Test]
        tmp.print indentation
        title = %("#{$1}")
        if $1.match /^(.*Controller)/
          title = $1
        end
        tmp.puts "describe #{title} do"
        if render_views
          tmp.puts indentation+"  render_views"
        end
        if modules_to_include
          tmp.puts indentation+"  "+modules_to_include
          modules_to_include = nil
        end
      elsif line =~ %r[def setup|setup do]
        tmp.print indentation
        tmp.puts "before do"
      elsif line =~ %r[def test_(.+)$]
        tmp.print indentation
        tmp.puts "it \"should #{$1.gsub(/_/, " ")}\" do"
      elsif line =~ %r{^\s*should\s+([^"'].*)} #shoulda syntax...
        tmp.print indentation
        tmp.puts "xit \"should be converted manually: #{$1.gsub('"', '\\"')}\""
      elsif line =~ %r{(?:test|should) ['"](.+)['"](.*)}
        tmp.print indentation
        tmp.puts "it \"should #{$1}\"#{$2}"
      elsif line =~ %r[assert_response :success]
        tmp.print indentation
        tmp.puts "response.should be_success"
      elsif line =~ %r[assert_response :redirect]
        tmp.print indentation
        tmp.puts "response.should be_redirect"
      elsif line =~ %r[assert_redirected_to (.+)$]
        tmp.print indentation
        tmp.puts "response.should redirect_to(#{$1})"
      elsif line =~ %r[assert_include (.+?), (.+?)(,.*)?$]
        tmp.print indentation
        tmp.puts "#{$2}.should include(#{$1})"
      elsif line =~ %r[assert_equal\s+(.*)$]
        #cut things the best way possible
        a = $1
        a =~ /^(\S+\(.*?\)),\s+(.+)$/ ||    #assert_equal Date.new(1, 2, 3), blabla
          a =~ /^(\[.*?\]),\s+(.+)$/ ||     #assert_equal [a, b, c], blabla
          a =~ /^(".+?"),\s+(.+)$/ ||       #assert_equal "admin, jsmith", blabla
          a =~ /^(.+?),\s+(.+)$/
        m1, m2 = $1, $2
        m2 = "(#{m2})" if m2 =~ /\S\s+\S/
        #check for errors
        raise "not implemented: m1 or m2 are nil (really)" if m1.nil? || m2.nil?
        raise "not implemented: m2 shouldn't be 'nil'" if m2.match(/nil/)
        #then go transform
        tmp.print indentation
        tmp.puts "#{m2}.should == #{m1}"
      elsif line =~ %r[assert assigns\(:([^\) ]*)\)$]
        tmp.print indentation
        tmp.puts "assigns[:#{$1}].should be_true"
      else
        unless line =~ /^class.*?Controller.*?rescue_action.*?end$/i or line =~ /require '.*?_controller'/i or line =~ /^#/
          tmp.puts line
        end
      end
    end
    tmp.close
    FileUtils.copy(tmp, file)
    %x(ruby -c #{file} >/dev/null)
  ensure
    tmp.close
    tmp.unlink
  end
end

dir = File.expand_path(Dir.pwd)

puts "* Migrating tests from #{Dir.pwd}"
unless ENV["FORCE"] == "yes" || (print "Confirmed? [O/n] "; $stdout.flush; $stdin.gets.chomp! =~ /^o$/i)
  puts "exiting..."
  exit 1
end

puts "* Moving tests from test/ to spec/"
FileUtils.mkdir_p("spec")
prepare_file_and_directories(Dir.new("test"), Dir.new("spec"))

puts "* Adjusting spec_helper"
spec_helper = "spec/spec_helper.rb"
$should_keep_spec_helper = true
if File.exists?(spec_helper)
  lines = File.readlines(spec_helper)
  if lines.size == 2 && lines[0] =~ /^#.*/ && lines[1] =~ /test_helper/
    $should_keep_spec_helper = false
    FileUtils.rm(spec_helper)
  end
end

puts "* Converting syntax to rspec"
Dir.glob("spec/**/*").each do |path|
  convert_test_unit_file_to_rspec(path) if path.match /(spec_helper|_spec)\.rb$/
end

puts "* We may run the rspec suite now"
if ENV["RUN"] == "yes" || (print "Confirmed? [O/n] "; $stdout.flush; $stdin.gets.chomp! =~ /^o$/i)
  Dir.chdir("../..") do
    cmd = %(rspec -Iplugins/redmine_base_rspec/spec #{dir})
    puts "cmd: #{cmd}"
    puts %x(#{cmd})
  end
end
