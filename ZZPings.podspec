#
#  Be sure to run `pod spec lint ZZPings.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  These will help people to find your library, and whilst it
  #  can feel like a chore to fill in it's definitely to your advantage. The
  #  summary should be tweet-length, and the description more in depth.
  #

  s.name         = "ZZPings"
  s.version      = "1.0.2"
  s.summary      = "ZZPings  return rtt and ttl for you and you are able to tell him the count of packets to send ."


  s.homepage     = "https://avinashtag@github.com/avinashtag/ZZPings"

  s.license      = { :type => "MIT", :file => "LICENSE" }



  s.author             = { "Avinash Tag" => "avi.tag@gmail.com" }
   s.ios.deployment_target = "8.1"
s.osx.deployment_target = "10.10"



  s.source       = { :git => "https://avinashtag@github.com/avinashtag/ZZPings.git", :tag => "1.0.2" }


  s.source_files  = "ZZPings", "ZZPings/**/*.{h,m}"



s.frameworks = "CFNetwork"

s.requires_arc = true


end
