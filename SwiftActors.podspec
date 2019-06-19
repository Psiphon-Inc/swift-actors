#
# Be sure to run `pod lib lint SwiftActors.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SwiftActors'
  s.version          = '1.1.1'
  s.summary          = 'Swift Actors Library'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = 'Actor model in Swift'

  s.homepage         = 'https://github.com/Psiphon-Inc/swift-actors'
  s.license          = { :type => 'GPLv3', :file => 'LICENSE' }
  s.author           = { 'Psiphon Inc.' => 'info@psiphon.ca' }
  s.source           = { :git => 'https://github.com/Psiphon-Inc/swift-actors.git', :tag => s.version.to_s }

  s.swift_version = '5.0'
  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.10'

  s.source_files = 'Sources/**/*'
  
  s.dependency 'PromisesSwift', '~> 1.2'
end