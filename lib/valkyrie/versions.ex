defmodule Valkyrie.Versions do
  use Ash.Domain,
    otp_app: :valkyrie

  resources do
    resource Valkyrie.Versions.CombinedVersion do
      define :list_versions,
        action: :read,
        default_options: [load: [:actor]]
    end
  end
end
