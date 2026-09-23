require 'json'
require 'net/http'
require 'openssl'
require 'jwt'

HOST = 'api.appstoreconnect.apple.com'
BUNDLE_ID = 'tech.hyperseek.gitstride'

key_id = ENV.fetch('ASC_KEY_ID')
key_path = ENV.fetch('ASC_KEY_PATH')
key = OpenSSL::PKey.read(File.read(key_path))
now = Time.now.to_i
token = JWT.encode(
  { iat: now - 60, exp: now + 600, aud: 'appstoreconnect-v1', sub: 'user' },
  key,
  'ES256',
  { kid: key_id, typ: 'JWT' }
)

def request_json(method, path, token, body = nil)
  uri = URI("https://#{HOST}#{path}")
  request = method.new(uri)
  request['Authorization'] = "Bearer #{token}"
  request['Content-Type'] = 'application/json' if body
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    errors = JSON.parse(response.body).fetch('errors', []).map { |error| "#{error['code']}: #{error['title']}" }
    abort "App Store Connect HTTP #{response.code}: #{errors.join('; ')}"
  end
  JSON.parse(response.body)
end

apps_path = "/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}&limit=2"
apps = request_json(Net::HTTP::Get, apps_path, token).fetch('data')
abort "No App Store Connect record for #{BUNDLE_ID}" unless apps.size == 1
app_id = apps.first.fetch('id')
availability = request_json(Net::HTTP::Get, "/v1/apps/#{app_id}/appAvailabilityV2", token).fetch('data')
abort 'Set up app availability in App Store Connect first' unless availability

availability_id = availability.fetch('id')
path = "/v2/appAvailabilities/#{availability_id}/territoryAvailabilities?limit=200&include=territory"
territories = request_json(Net::HTTP::Get, path, token).fetch('data')
china = territories.select { |item| item.dig('relationships', 'territory', 'data', 'id') == 'CHN' }
abort "Expected one China mainland territory; found #{china.size}" unless china.size == 1

entry = china.first
if entry.dig('attributes', 'available')
  body = { data: { type: 'territoryAvailabilities', id: entry.fetch('id'), attributes: { available: false } } }
  request_json(Net::HTTP::Patch, "/v1/territoryAvailabilities/#{entry.fetch('id')}", token, body)
end

territories = request_json(Net::HTTP::Get, path, token).fetch('data')
china = territories.find { |item| item.dig('relationships', 'territory', 'data', 'id') == 'CHN' }
abort 'China mainland remains available' unless china && china.dig('attributes', 'available') == false
puts "Confirmed China mainland unavailable for #{BUNDLE_ID}; other territories unchanged."
