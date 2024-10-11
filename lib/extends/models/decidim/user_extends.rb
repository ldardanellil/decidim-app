# frozen_string_literal: true

require "active_support/concern"
module UserExtends
  extend ActiveSupport::Concern

  included do
    def moderator?
      Decidim.participatory_space_manifests.map do |manifest|
        participatory_space_type = manifest.model_class_name.constantize
        return true if participatory_space_type.moderators(organization).exists?(id: id)
      end
      false
    end
  end
end

Decidim::User.include(UserExtends)
