gem 'albacore', '~> 0.2.7'
gem 'net-sftp', '~> 2.0.5'

require 'albacore'
require 'net/sftp'
require 'uri'

include Rake::DSL

# Fix for confusing build error while running under a Visual Studio command prompt.
# See http://devlicio.us/blogs/derik_whittaker/archive/2008/02/29/nasty-msbuild-error-msb4126-quot-debug-hpd-quot-issue.aspx
ENV["PLATFORM"] = nil

# The default task prints all possible tasks.
task :default do sh %{rake --describe} end

# Zip files will be placed below this directory.
RedistDirName = "redist"

BitsquidRevision="r7"
def product(platform, vs_version)
	return "hlsl2glsl-#{platform}-#{vs_version}-#{BitsquidRevision}"
end

# --------------------------------------------------
# Utility functions.
# --------------------------------------------------

# Configures the supplied Albacore MSBuild task.
def configure_msbuild(msbuild, solution, configuration, platform)
	# We must do a clean rebuild, since the output directories are the same for both VC9 and VC10 solutions.
	msbuild.targets = [:Build]
	msbuild.properties = { :Configuration => configuration, :Platform => platform }
	msbuild.solution = solution
end

# Configures the supplied Albacore Output task.
def configure_redist_dir(output, zip_file_name, platforms, compiler)
	working_dir = File.join(RedistDirName, zip_file_name)
	makedirs working_dir

	output.from "."
	output.to File.join(working_dir, zip_file_name)
	
	Configurations.each do |configuration|
		for platform in platforms
			output.file "lib/#{platform}/#{configuration}/hlsl2glsl.lib"
			output.file "build/#{compiler}/#{platform}/#{configuration}/hlsl2glsl.pdb", :as => "lib/#{platform}/#{configuration}/hlsl2glsl.pdb"
		end
	end
	
	output.dir "include"
	output.file "LICENSE.txt"
	output.file "README.md"
end

# Configures the supplied Albacore Zip task.
def configure_redist_zip(zip, zip_file_name)
	zip.directories_to_zip File.join(RedistDirName, zip_file_name)
	zip.output_file = zip_file_name + ".zip"
	zip.output_path = RedistDirName
end

# Returns a rake task that invokes the MSBuild 4.0/4.5 build system.
MSBuild2012 = lambda do |rake_task_name, solution, solution_platform, config|
	msbuild rake_task_name do |build|
		configure_msbuild(build, solution, config, solution_platform)
	end
end


# Returns a rake task that invokes the MSBuild 4.0 build system.
MSBuild2010 = lambda do |rake_task_name, solution, solution_platform, config|
	msbuild rake_task_name do |build|
		configure_msbuild(build, solution, config, solution_platform)
	end
end

# Returns a rake task that invokes the MSBuild 3.5 build system.
MSBuild2008 = lambda do |rake_task_name, solution, solution_platform, config|
	msbuild rake_task_name do |build|
		configure_msbuild(build, solution, config, solution_platform)
		build.use :net35
	end
end


# --------------------------------------------------
# Define common rake tasks.
# --------------------------------------------------

namespace "just" do
	desc "Just erase any existing redist dir"
	task :delete_redist_dir do |task|
		rm_rf RedistDirName
	end
end

# --------------------------------------------------
# Define rake task permutations.
# --------------------------------------------------

Configurations = %w{ Debug Release }
WindowsArchs = [
	{ :compiler_config => :Win32, :output_folder_name => :w32, :name => "32bit" },
	{ :compiler_config => :x64, :output_folder_name => :w64, :name => "64bit" }
]

Settings = {
	:windows => {
		:name => "Windows",
		:vs_versions => {
			:vc10 => {
				:compiler => MSBuild2010,
				:solution => "hlslang_vs2010.sln",
				:zip_file => "hlsl2glsl_vc10",
				:platforms => WindowsArchs },
			:vc11 => {
				:compiler => MSBuild2012,
				:solution => "hlslang_vs2012.sln",
				:zip_file => "hlsl2glsl_vc11",
				:platforms => WindowsArchs } } } }

Settings.each do |platform, platform_settings|
	platform_name = platform_settings[:name]      # => "Windows"
	vs_versions = platform_settings[:vs_versions] # => [:vc9, :vc10]
	

	# --------------------------------------------------
	# Define Visual Studio version-specific rake tasks.
	# --------------------------------------------------

	vs_versions.each do |vs_version, vs_settings|
		vs_version_name = vs_version.to_s.upcase
		rake_task_name = "#{platform}_#{vs_version}" # => "pc_vc10"
		zip_file = product(platform, vs_version)            # => "hlsl2glsl-vc11-windows-r2"

		namespace "just:build" do
			compiler = vs_settings[:compiler]          # => <Proc>
			solution = vs_settings[:solution]          # => "hlslang_vc2010.sln"
			solution_platforms = vs_settings[:platforms] # =>  [ :Win32, :x64 ]

			Configurations.each do |config|
				for solution_platform in solution_platforms
					desc "Just build #{config} #{platform_name} libs for #{vs_version_name} #{solution_platform[:name]}"
					compiler.call("#{platform}_#{vs_version}_#{config}_#{solution_platform[:name]}", solution, solution_platform[:compiler_config], config)
				end

				desc "Just build #{config} #{platform_name} libs for #{vs_version_name}"
				task "#{platform}_#{vs_version}_#{config}" => solution_platforms.map { |solution_platform| "#{platform}_#{vs_version}_#{config}_#{solution_platform[:name]}" }
			end

			desc "Just build all #{platform_name} libs for #{vs_version_name}"
			task rake_task_name => Configurations.map { |config| "#{platform}_#{vs_version}_#{config}" }
		end

		namespace "just:make_redist_dir" do
			desc "Just prepare #{platform_name} package for #{vs_version_name}"
			output rake_task_name do |output|
				configure_redist_dir(output, zip_file, vs_settings[:platforms].map { |p| p[:output_folder_name] }, vs_version)
			end
		end

		namespace "make_redist_dir" do
			desc "Prepare #{platform_name} package for #{vs_version_name}"
			task rake_task_name => ["just:delete_redist_dir", "just:build:#{rake_task_name}", "just:make_redist_dir:#{rake_task_name}"]
		end

		namespace "just:make_zip" do
			desc "Just zip #{platform_name} package for #{vs_version_name}"
			zip rake_task_name do |zip|
				configure_redist_zip(zip, zip_file)
			end
		end

		namespace "make_zip" do
			desc "Zip #{platform_name} package for #{vs_version_name}"
			task rake_task_name => %w{ make_redist_dir just:make_zip }.map { |ns| ns + ":" + rake_task_name }
		end

		namespace "just:copy" do
			desc "Just deploy #{platform_name} zip file for #{vs_version_name}"
			task rake_task_name, [:dest_dir] do |task, args|
				dest_dir = args.dest_dir # => "\\server\"
				raise "Must supply dest_dir parameter" if dest_dir.nil?
				cp "#{RedistDirName}/#{zip_file}.zip", dest_dir
			end
		end

		namespace "copy" do
			desc "Deploy #{platform_name} zip file for #{vs_version_name}"
			task rake_task_name, [:dest_dir] => %w{ make_zip just:copy }.map { |ns| ns + ":" + rake_task_name }
		end

		namespace "just:upload" do
			desc "Just deploy #{platform_name} zip file for #{vs_version_name}"
			task rake_task_name, [:dest_dir_uri] do |task, args|
				dest_dir_uri = args.dest_dir_uri # => "sftp://usr:pwd@127.0.0.1/dependencies/lib"
				raise "Must supply dest_dir_uri parameter" if dest_dir_uri.nil?
				uri = URI.parse dest_dir_uri

				Net::SFTP.start(uri.host, uri.user, :password => uri.password) do |sftp|
					sftp.upload!("#{RedistDirName}/#{zip_file}.zip", "#{uri.path}/#{zip_file}.zip")
				end
			end
		end

		namespace "upload" do
			desc "Deploy #{platform_name} zip file for #{vs_version_name}"
			task rake_task_name, [:dest_dir_uri] => %w{ make_zip just:upload }.map { |ns| ns + ":" + rake_task_name }
		end
	end


	# --------------------------------------------------
	# Define platform-specific umbrella rake tasks.
	# --------------------------------------------------

	namespace "just:build" do
		desc "Just build all #{platform_name} libs"
		task platform => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "just:make_redist_dir" do
		desc "Just prepare all #{platform_name} packages"
		task platform => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "make_redist_dir" do
		desc "Prepare all #{platform_name} packages"
		task platform => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "just:make_zip" do
		desc "Just zip all #{platform_name} packages"
		task platform => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "make_zip" do
		desc "Zip all #{platform_name} packages"
		task platform => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "just:copy" do
		desc "Just deploy all #{platform_name} zip files"
		task platform, [:dest_dir] => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "copy" do
		desc "Deploy all #{platform_name} zip files"
		task platform, [:dest_dir] => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "just:upload" do
		desc "Just deploy all #{platform_name} zip files"
		task platform, [:dest_dir_uri] => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end

	namespace "upload" do
		desc "Deploy all #{platform_name} zip files"
		task platform, [:dest_dir_uri] => vs_versions.keys.map { |vs_version| "#{platform}_#{vs_version}" }
	end
end


# --------------------------------------------------
# Define outer umbrella rake tasks.
# --------------------------------------------------

platforms = Settings.keys

namespace "just:build" do
	desc "Just build all libs"
	task :all => platforms
end

namespace "just:make_redist_dir" do
	desc "Just prepare all packages"
	task :all => platforms
end

namespace "make_redist_dir" do
	desc "Prepare all packages"
	task :all => platforms
end

namespace "just:make_zip" do
	desc "Just zip all packages"
	task :all => platforms
end

namespace "make_zip" do
	desc "Zip all packages"
	task :all => platforms
end

namespace "just:copy" do
	desc "Just deploy all zip files"
	task :all, [:dest_dir] => platforms
end

namespace "copy" do
	desc "Deploy all zip files"
	task :all, [:dest_dir] => platforms
end

namespace "just:upload" do
	desc "Just deploy all zip files"
	task :all, [:dest_dir] => platforms
end

namespace "upload" do
	desc "Deploy all zip files"
	task :all, [:dest_dir] => platforms
end
