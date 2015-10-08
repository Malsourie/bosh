module Bosh
  module Director
    module DeploymentPlan
      class DeploymentRepo
        def find_or_create_by_name(name)
          deployment = Models::Deployment.find(name: name)
          return deployment if deployment

          canonical_name = DnsManager.canonical(name)
          Models::Deployment.db.transaction do
            Models::Deployment.each do |other|
              if DnsManager.canonical(other.name) == canonical_name
                raise DeploymentCanonicalNameTaken,
                  "Invalid deployment name `#{name}', canonical name already taken (`#{canonical_name}')"
              end
            end
            Models::Deployment.create(name: name)
          end
        end
      end
    end
  end
end
