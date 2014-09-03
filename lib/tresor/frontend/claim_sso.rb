module Tresor
  module Frontend
    module ClaimSSO
      extend ActiveSupport::Autoload

      autoload :RedirectToSSOFrontendHandler
      autoload :ClaimSSOSecurityToken
      autoload :ProcessSAMLResponseFrontendHandler
    end
  end
end