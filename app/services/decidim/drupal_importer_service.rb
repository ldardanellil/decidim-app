module Decidim
  class DrupalImporterService
    def self.run(**_args)
      new.execute
    end

    def initialize(**args)
      puts "initializing..."
      @path = args[:path]
      @organization = args[:organization]
      @dev = true
    end

    def execute
      puts "executing..."
      pp = Decidim::ParticipatoryProcess.first

      pp.components.destroy_all

      create_meeting!(@org, pp)
      create_page!(@org, pp)
      create_proposal!(@org, pp)

      Dir.glob("backups/amelioration-de-la-desserte-en-transport-en-commun-de-la-zone/*.pdf").each do |file|
        content = File.open(file)
        file = {
          io: content,
          filename: File.basename(file),
          content_type: "application/pdf",
          name: transform_file_name(File.basename(file, ".*"))
        }

        attachment =
          {
            name: file[:name],
            filename: file[:filename],
            description: file[:name],
            content_type: file[:content_type],
            attached_to: pp,
            file: {
              io: file[:io],
              filename: file[:filename],
              content_type: file[:content_type],
              metadata: nil
            }
          }

        Decidim::Attachment.create!(
          title: { "fr" => attachment[:name] },
          description: { "fr" => attachment[:description] },
          attachment_collection: nil,
          content_type: attachment[:content_type],
          attached_to: pp,
          file: ActiveStorage::Blob.create_and_upload!(
            io: attachment.dig(:file, :io),
            filename: attachment.dig(:file, :filename),
            content_type: attachment.dig(:file, :content_type),
            metadata: attachment.dig(:file, :metadata)
          ))

      rescue ActiveRecord::RecordInvalid => e
        case e.message
        when /Validation failed: Title has already been taken/
          puts "Attachment already exists"
        when /Validation failed: File file size must be less than or equal to/
          org = attachment[:attached_to].organization
          limit = ActiveSupport::NumberHelper::NumberToHumanSizeConverter.convert(org.maximum_upload_size, {})
          human_filesize = ActiveSupport::NumberHelper::NumberToHumanSizeConverter.convert(attachment[:file][:io].size, {})
          puts "Attachment file size too big for '#{attachment[:name]}': #{human_filesize}"
          puts "Max: #{limit} current: #{human_filesize}"
        else
          puts "Error: '#{e.message}'"
        end

        next
      end
    end

    private

    def get_file(url)
      file = URI.open(url)
      return file
    end

    def create_meeting!(org, pp)
      Decidim::Component.create!(
        name: "RENCONTRES",
        manifest_name: "meetings",
        participatory_space: pp,
        published_at: Time.zone.now,
        settings: {
          "title" => { "fr" => "RENCONTRES" },
          "description" => { "fr" => "Rencontres" },
          "position" => 1,
          "organization" => org
        }
      )
    end

    def create_page!(org, pp)
      Decidim::Component.create!(
        name: "BILANS & DÉCISIONS",
        manifest_name: "pages",
        participatory_space: pp,
        published_at: Time.zone.now,
        settings: {
          "title" => { "fr" => "BILANS & DÉCISIONS" },
          "description" => { "fr" => "Bilans" },
          "position" => 2,
          "organization" => org
        }
      )
    end

    def create_proposal!(org, pp)
      Decidim::Component.create!(
        name: "AVIS ET REACTIONS",
        manifest_name: "proposals",
        participatory_space: pp,
        published_at: Time.zone.now,
        settings: {
          "title" => { "fr" => "PROPOSITIONS" },
          "description" => { "fr" => "Propositions" },
          "position" => 3,
          "organization" => org
        }
      )
    end

    def transform_file_name(filename)
      filename = filename.gsub("_", " ")
      filename = filename.gsub("'", "")
      filename = filename.gsub("\"", "")
      filename = filename.gsub("(", "")
      filename = filename.gsub(")", "")

      filename = filename.split.map(&:capitalize).join(' ')
      return filename
    end
  end
end