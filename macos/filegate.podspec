#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint filegate.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'filegate'
  s.version          = '1.10.0'
  s.summary          = 'A macOS 12+ file chooser plugin with native file streaming.'
  s.description      = <<-DESC
A macOS 12+ file chooser plugin with native file streaming.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'lingjhf' => 'lingj.jhf@outlook.com' }

  s.source           = { :path => '.' }
  s.source_files = 'filegate/Sources/filegate/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact. For more information, see:
  # https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'filegate_privacy' => ['filegate/Sources/filegate/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
