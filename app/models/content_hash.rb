require "digest"
require "json"

module ContentHash
  FORMAT = /\A[0-9a-f]{64}\z/

  def self.calculate(*values)
    Digest::SHA256.hexdigest(Digest::SHA256.digest(JSON.generate(values)))
  end
end
