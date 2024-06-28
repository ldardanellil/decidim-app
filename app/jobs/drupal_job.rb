# frozen_string_literal: true

class DrupalJob < ApplicationJob
  queue_as :exports

  def perform
    Decidim::DrupalImporterService.run
  end
end
