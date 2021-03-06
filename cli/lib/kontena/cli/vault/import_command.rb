module Kontena::Cli::Vault
  class ImportCommand < Kontena::Command
    include Kontena::Cli::Common
    include Kontena::Cli::GridOptions

    banner "Imports secrets to Vault from a YAML file. Secrets with a null value will be deleted from Vault."

    option "--force", :flag, "Force import", default: false, attribute_name: :forced
    option '--json', :flag, "Input JSON instead of YAML"
    option '--skip-null', :flag, "Do not remove keys with null values"
    option '--empty-is-null', :flag, "Treat empty values as null"

    parameter '[PATH]', "Input from file in PATH (default: STDIN)"

    requires_current_master

    def parsed_input
      require "json"
      require "safe_yaml"
      SafeYAML::OPTIONS[:default_mode] = :safe
      json? ? JSON.load(input) : YAML.safe_load(input)
    end

    def input
      path ? File.read(path) : stdin_input("Enter secrets YAML", :multiline)
    end

    def execute
      require_current_grid

      updates = []
      deletes = []

      parsed_input.map do |k,v|
        case v
        when String, Numeric, TrueClass, FalseClass
          if empty_is_null? && v.to_s.empty?
            deletes << k.to_s
          else
            updates << [k.to_s, v.to_s]
          end
        when NilClass
          deletes << k.to_s
        else
          exit_with_error "Invalid value type #{v.class} for #{k}."
        end
      end

      if updates.empty? && deletes.empty?
        exit_with_error "No secrets loaded"
      end

      unless forced?
        puts "About to.."
        puts "  * #{Kontena.pastel.yellow("IMPORT")} #{updates.size} secret#{"s" if updates.size > 1}" unless updates.empty?
        puts "  * #{Kontena.pastel.red("DELETE")} #{deletes.size} secret#{"s" if deletes.size > 1}" unless deletes.empty?
        confirm
      end

      unless updates.empty?
        spinner "Updating #{updates.size} secrets" do |spin|
          updates.each do |key_value_pair|
            spin.fail! unless Kontena.run(['vault', 'update', '--upsert', '--silent'] + key_value_pair)
          end
        end
      end

      unless deletes.empty? || skip_null?
        spinner "Deleting #{deletes.size} secrets" do |spin|
          deletes.map(&:shellescape).each do |key_to_delete|
            spin.fail! unless Kontena.run(['vault', 'rm', '--silent', '--force', key_to_delete])
          end
        end
      end
    end
  end
end
