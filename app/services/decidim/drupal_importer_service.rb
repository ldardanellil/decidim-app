module Decidim
  class DrupalImporterService
    def self.run(**args)
      new(**args).execute
    end

    def initialize(**args)
      puts "initializing..."
      @path = args[:path]
      @organization = args[:organization]
      @dev = true
    end

    def execute
      puts "executing..."
      drupal_page = DrupalPage.scrape(url: "https://participation.bordeaux-metropole.fr/participation/urbanisme/martignas-sur-jalle-creer-un-centre-ville-encore-plus-accueillant-et-facile", slug: "martignas-sur-jalle-creer-un-centre-ville-encore-plus-accueillant-et-facile")
      pp = Decidim::ParticipatoryProcess.find_by(slug: drupal_page.slug)
      if pp.blank?
        pp = Decidim::ParticipatoryProcess.create!(
          title: { "fr" => drupal_page.title },
          slug: drupal_page.slug,
          subtitle: { "fr" => drupal_page.title },
          description: { "fr" => drupal_page.description },
          short_description: { "fr" => drupal_page.description },
          organization: @organization,
          start_date: Time.zone.now,
          end_date: Time.zone.now + 1.minute)
      end

      create_meeting!(@organization, pp)
      create_page!(@organization, pp)
      create_proposal!(@organization, pp)

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

      puts "Done"
    end

    private

    def create_meeting!(org, pp)
      Decidim::Component.create!(
        name: "RENCONTRES 📍",
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
        name: "AVIS ET REACTIONS 💡",
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

  class DrupalPage
    attr_reader :url, :slug, :md5, :nokogiri_document, :title, :description, :drupal_node_id, :thematique, :pdf_attachments, :participatory_process_url, :decidim_participatory_process_id
    def self.scrape(**args)
      new(**args).scrape
    end

    def initialize(**args)
      @url = args[:url]
      @slug = args[:slug]
      @md5 = Digest::MD5.hexdigest(@url)
    end

    def migration_metadata
      {
        url: @url,
        title: @title,
        short_url: @short_url,
        drupal_node_id: @drupal_node_id,
        thematique: @thematique,
        attachments_count: @pdf_attachments.length,
        decidim_participatory_process_id: @decidim_participatory_process_id,
        participatory_process_url: @participatory_process_url
      }
    end

    def attributes
      {
        html_page: "backups/#{@md5}/#{@md5}.html",
        title: @title,
        url: @url,
        short_url: @short_url,
        drupal_node_id: @drupal_node_id,
        thematique: @thematique,
        description: @description,
        pdf_attachments: @pdf_attachments
      }
    end

    def scrape
      fetch_html
      return if @nokogiri_document.blank?

      set_thematique
      set_drupal_node_id
      set_title
      set_description
      set_pdf_attachments
      save!
      save_json_resume!

      self
    end

    def fetch_html
      Faraday.default_adapter = :net_http
      req = Faraday.get(@url)
      @html = req.body if req.status == 200
      @nokogiri_document = Nokogiri::HTML(@html) if @html.present?
    end

    def set_participatory_process_url(url)
      @participatory_process_url = url
    end

    def set_decidim_participatory_process_id(id)
      @decidim_participatory_process_id = id
    end

    def set_title
      @title = @nokogiri_document.css("#page-title h1").text
    end

    def set_description
      @description = @nokogiri_document.css(".field-name-field-descriptif .field-item.even").children.to_s
    end

    def set_pdf_attachments
      unique_links = []
      @pdf_attachments = @nokogiri_document.css("a.doc-name").map do |link|
        next if link['href'].blank?
        next unless link['href'].include?(".pdf")
        next if link.text.blank?
        next if unique_links.include?(link['href'])

        unique_links << link['href']
        { title: link.text&.strip, href: link['href'] }
      end.compact.uniq
    end

    def set_drupal_node_id
      @short_url = @nokogiri_document.css("link[rel='shortlink']").attr('href').value
      @drupal_node_id = @short_url&.split("/")&.last || 0
    end

    def set_thematique
      breadcrumbs = @nokogiri_document.css("ol.breadcrumb li")
      @thematique = if breadcrumbs.length > 2
                      @nokogiri_document.css("ol.breadcrumb li")[-2].text
                    else
                      ""
                    end
    end

    def save_json_resume!
      return if @title.blank? || @description.blank?
      Dir.mkdir("backups/#{@md5}") unless File.exists?("backups/#{@md5}")
      File.open("backups/#{@md5}/#{@md5}.json", "w") { |file| file.write(JSON.pretty_generate(attributes)) }
    end

    def save!
      return if @html.blank?

      Dir.mkdir("backups/#{@md5}") unless File.exists?("backups/#{@md5}")
      File.open("backups/#{@md5}/#{@md5}.html", "w") { |file| file.write(@html) }
    end
  end
end