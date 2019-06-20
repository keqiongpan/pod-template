require 'fileutils'
require 'colored2'

module Pod
  class TemplateConfigurator

    attr_reader :pod_name, :pods_for_podfile, :libs_for_cartfile, :prefixes, :test_example_file, :username, :email, :custom_user_name, :custom_user_email, :custom_github_account_name, :custom_xcode_organization_name, :custom_xcode_bundle_identifier_prefix

    def initialize(pod_name)
      @pod_name = pod_name
      @pods_for_podfile = []
      @libs_for_cartfile = []
      @prefixes = []
      @message_bank = MessageBank.new(self)
    end

    def ask(question)
      answer = ""
      loop do
        puts "\n#{question}?"

        @message_bank.show_prompt
        answer = gets.chomp

        break if answer.length > 0

        print "\nYou need to provide an answer."
      end
      answer
    end

    def ask_with_answers(question, possible_answers)

      print "\n#{question}? ["

      print_info = Proc.new {

        possible_answers_string = possible_answers.each_with_index do |answer, i|
           _answer = (i == 0) ? answer.underlined : answer
           print " " + _answer
           print(" /") if i != possible_answers.length-1
        end
        print " ]\n"
      }
      print_info.call

      answer = ""

      loop do
        @message_bank.show_prompt
        answer = gets.downcase.chomp

        answer = "yes" if answer == "y"
        answer = "no" if answer == "n"

        # default to first answer
        if answer == ""
          answer = possible_answers[0].downcase
          print answer.yellow
        end

        break if possible_answers.map { |a| a.downcase }.include? answer

        print "\nPossible answers are ["
        print_info.call
      end

      answer
    end

    def ask_with_default(question, default_value)
      answer = nil
      loop do
        print "\n#{question} [" + default_value.underlined + "]\n"

        @message_bank.show_prompt
        answer = gets.chomp

        break if answer.length <= 0
        answer = answer.strip
        break if answer.length > 0

        print '\nYour need input a valid value.'.red
      end
      answer = answer.empty? ? nil : answer
      print (answer || default_value).yellow
      answer
    end

    def confirm_all_variable_values
      @custom_user_name = self.ask_with_default("Do you want change the default value of `${USER_NAME}'?`", user_name)
      @custom_user_email = self.ask_with_default("Do you want change the default value of `${USER_EMAIL}'?`", user_email)
      @custom_github_account_name = self.ask_with_default("Do you want change the default value of `${GITHUB_ACCOUNT_NAME}'?`", github_account_name)
      @custom_xcode_organization_name = self.ask_with_default("Do you want change the default value of `Organization Name'?`", xcode_organization_name)
      @custom_xcode_bundle_identifier_prefix = self.ask_with_default("Do you want change the default value of `Bundle Identifier Prefix'?`", xcode_bundle_identifier_prefix)
    end

    def run
      @message_bank.welcome_message
      confirm_all_variable_values

      platform = self.ask_with_answers("What platform do you want to use?", ["iOS", "macOS"]).to_sym

      case platform
        when :macos
          ConfigureMacOSSwift.perform(configurator: self)
        when :ios
          framework = self.ask_with_answers("What language do you want to use?", ["ObjC", "Swift"]).to_sym
          case framework
            when :swift
              ConfigureSwift.perform(configurator: self)

            when :objc
              ConfigureIOS.perform(configurator: self)
          end
      end

      replace_variables_in_files
      clean_template_files
      rename_template_files
      add_pods_to_podfile
      add_libs_to_cartfile
      customise_prefix
      rename_classes_folder
      ensure_carthage_compatibility
      reinitialize_git_repo
      run_carthage_update
      run_pod_install

      @message_bank.farewell_message
    end

    #----------------------------------------#

    def ensure_carthage_compatibility
      # FileUtils.ln_s('Example/Pods/Pods.xcodeproj', '_Pods.xcodeproj')
    end

    def run_pod_install
      puts "\nRunning " + "pod install".magenta + " on your example."
      puts ""

      Dir.chdir("Example") do
        system "pod install"
      end

      `git add Example/#{pod_name}Example.xcodeproj/project.pbxproj`
      `git commit -m "Initial commit"`
    end

    def run_carthage_update
      puts "\nRunning " + "carthage update".magenta + " on your new library."
      puts ""

      system "carthage update"
    end

    def clean_template_files
      ["./**/.gitkeep", "configure", "_CONFIGURE.rb", "README.md", "LICENSE", "templates", "setup", "CODE_OF_CONDUCT.md"].each do |asset|
        `rm -rf #{asset}`
      end
    end

    def replace_variables_in_files
      file_names = ['POD_LICENSE', 'POD_README.md', 'NAME.podspec', '.travis.yml', podfile_path]
      file_names.each do |file_name|
        text = File.read(file_name)
        text.gsub!("${POD_NAME}", @pod_name)
        text.gsub!("${REPO_NAME}", @pod_name.gsub('+', '-'))
        text.gsub!("${GITHUB_ACCOUNT_NAME}", github_account_name)
        text.gsub!("${USER_NAME}", user_name)
        text.gsub!("${USER_EMAIL}", user_email)
        text.gsub!("${YEAR}", year)
        text.gsub!("${DATE}", date)
        File.open(file_name, "w") { |file| file.puts text }
      end
    end

    def add_pod_to_podfile podname
      @pods_for_podfile << podname
    end

    def add_pods_to_podfile
      # podfile = File.read podfile_path
      # podfile_content = @pods_for_podfile.map do |pod|
      #   "pod '" + pod + "'"
      # end.join("\n    ")
      # podfile.gsub!("${INCLUDED_PODS}", podfile_content)
      # File.open(podfile_path, "w") { |file| file.puts podfile }
    end

    def add_lib_to_cartfile libname
      @libs_for_cartfile << libname
    end

    def add_libs_to_cartfile
      cartfile = File.read cartfile_path
      cartfile_content = @libs_for_cartfile.map do |lib|
        "github \"" + lib + "\""
      end.join("\n")
      cartfile.gsub!("${INCLUDED_LIBS}", cartfile_content)
      File.open(cartfile_path, "w") { |file| file.puts cartfile }
    end

    def add_line_to_pch line
      @prefixes << line
    end

    def customise_prefix
      prefix_path = pod_name + "Tests/Prefix.pch"
      return unless File.exists? prefix_path

      pch = File.read prefix_path
      pch.gsub!("${INCLUDED_PREFIXES}", @prefixes.join("\n  ") )
      File.open(prefix_path, "w") { |file| file.puts pch }
    end

    def set_test_framework(test_type, extension, folder)
      content_path = "setup/test_examples/" + test_type + "." + extension
      tests_path = "templates/" + folder + "/PROJECTTests/Tests." + extension
      tests = File.read tests_path
      tests.gsub!("${TEST_EXAMPLE}", File.read(content_path) )
      File.open(tests_path, "w") { |file| file.puts tests }
    end

    def rename_template_files
      FileUtils.mv "POD_README.md", "README.md"
      FileUtils.mv "POD_LICENSE", "LICENSE"
      FileUtils.mv "NAME.podspec", "#{pod_name}.podspec"
    end

    def rename_classes_folder
      FileUtils.mv "Pod", @pod_name
    end

    def reinitialize_git_repo
      `rm -rf .git`
      `git init`
      `git add -A`
    end

    def validate_user_details
        return (user_email.length > 0) && (user_name.length > 0)
    end

    #----------------------------------------#

    def user_name
      (@custom_user_name || ENV['GIT_COMMITTER_NAME'] || `git config user.name` || github_user_name || `<GITHUB_USERNAME>` ).strip
    end

    def user_email
      (@custom_user_email || ENV['GIT_COMMITTER_EMAIL'] || `git config user.email`).strip
    end

    def github_user_name
      github_user_name = `security find-internet-password -s github.com | grep acct | sed 's/"acct"<blob>="//g' | sed 's/"//g'`.strip
      is_valid = github_user_name.empty? or github_user_name.include? '@'
      return is_valid ? nil : github_user_name
    end

    def github_account_name
      (@custom_github_account_name || ENV['GITHUB_ACCOUNT_NAME'] || github_user_name || `<GITHUB_ACCOUNT_NAME>`).strip
    end

    def xcode_organization_name
      return @custom_xcode_organization_name if @custom_xcode_organization_name
      xcode_organization_name = `defaults read -app Xcode IDETemplateOptions | grep organizationName | sed 's/^[^=]*=[[:space:]]*"\\{0,1\\}//' | sed 's/"\\{0,1\\}[[:space:]]*;[[:space:]]*$//'`.strip
      return xcode_organization_name.empty? ? user_name : xcode_organization_name
    end

    def xcode_bundle_identifier_prefix
      return @custom_xcode_bundle_identifier_prefix if custom_xcode_bundle_identifier_prefix
      xcode_bundle_identifier_prefix = `defaults read -app Xcode IDETemplateOptions | grep bundleIdentifierPrefix | sed 's/^[^=]*=[[:space:]]*"\\{0,1\\}//' | sed 's/"\\{0,1\\}[[:space:]]*;[[:space:]]*$//'`.strip
      return xcode_bundle_identifier_prefix.empty? ? ("io.github." + github_account_name) : xcode_bundle_identifier_prefix
    end

    def year
      Time.now.year.to_s
    end

    def date
      Time.now.strftime "%Y/%m/%d"
    end

    def podfile_path
      'Example/Podfile'
    end

    def cartfile_path
      'Cartfile.private'
    end

    #----------------------------------------#
  end
end
