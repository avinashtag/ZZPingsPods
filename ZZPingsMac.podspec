#
#  Be sure to run `pod spec lint ZZPingsMac.podspec.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

s.name         = "ZZPingsMac"
s.version      = "1.0.2"
s.summary      = "ZZPings  return rtt and ttl for you and you are able to tell him the count of packets to send ."


s.homepage     = "https://code.rsint.net/tag_a/ZZPings"


s.license      = { :type => "MIT", :file => "LICENSE" }


s.author             = { "Avinash Tag" => "avinash.tag@rohde-schwarz.com }

s.osx.deployment_target = "10.10"
s.source       = { :git => "https://code.rsint.net/tag_a/ZZPings.git", :tag => "1.0.2" }

s.source_files  = "ZZPings", "ZZPings/**/*.{h,m}"



s.frameworks = "CFNetwork"

s.requires_arc = true



end
