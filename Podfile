inhibit_all_warnings!

target 'dashwallet' do
  platform :ios, '18.0'

  # Direct app-owned dependencies retained after the legacy wallet pod unlink.
  pod 'CocoaLumberjack', '3.7.2'
  pod 'DSDynamicOptions', '0.1.2'
  pod 'DWAlertController', '0.2.1'
  pod 'SQLite.swift', '~> 0.15.3'
  pod 'SQLiteMigrationManager.swift', '0.8.3'
  pod 'CloudInAppMessaging', '0.1.0'
  pod 'FirebaseStorage', '8.15.0'
  # CoreOnly provides the `Firebase` umbrella module (Firebase.h + its module
  # map) that `@import Firebase` / `import Firebase` resolve against. It used to
  # arrive implicitly as a dependency of Firebase/DynamicLinks; that subspec was
  # removed, so depend on it directly.
  pod 'Firebase/CoreOnly'
  pod 'SSZipArchive'
  pod 'KVO-MVVM', '0.5.6'
  pod 'UIViewController-KeyboardAdditions', '1.2.1'
  pod 'MBProgressHUD', '1.1.0'
  pod 'MMSegmentSlider', :git => 'https://github.com/podkovyrin/MMSegmentSlider', :commit => '2d91366'
  pod 'CocoaImageHashing', :git => 'https://github.com/ameingast/cocoaimagehashing.git', :commit => 'ad01eee'
  pod 'SDWebImage', '5.21.0', :modular_headers => true
  pod 'SDWebImageSwiftUI', '3.1.3', :modular_headers => true
  pod 'Moya', '~> 15.0'
  pod 'SwiftJWT', '3.6.200'
  pod 'TOCropViewController', '2.6.1'
  pod 'lottie-ios', '4.5.2'
  # Debugging purposes
  #  pod 'Reveal-SDK', :configurations => ['Debug']
  
end

target 'dashpay' do
  platform :ios, '18.0'

  # Direct app-owned dependencies retained after the legacy wallet pod unlink.
  pod 'CocoaLumberjack', '3.7.2'
  pod 'DSDynamicOptions', '0.1.2'
  pod 'DWAlertController', '0.2.1'
  pod 'SQLite.swift', '~> 0.15.3'
  pod 'SQLiteMigrationManager.swift', '0.8.3'
  pod 'CloudInAppMessaging', '0.1.0'
  pod 'FirebaseStorage', '8.15.0'
  # CoreOnly provides the `Firebase` umbrella module (Firebase.h + its module
  # map) that `@import Firebase` / `import Firebase` resolve against. It used to
  # arrive implicitly as a dependency of Firebase/DynamicLinks; that subspec was
  # removed, so depend on it directly.
  pod 'Firebase/CoreOnly'
  pod 'SSZipArchive'
  pod 'KVO-MVVM', '0.5.6'
  pod 'UIViewController-KeyboardAdditions', '1.2.1'
  pod 'MBProgressHUD', '1.1.0'
  pod 'MMSegmentSlider', :git => 'https://github.com/podkovyrin/MMSegmentSlider', :commit => '2d91366'
  pod 'CocoaImageHashing', :git => 'https://github.com/ameingast/cocoaimagehashing.git', :commit => 'ad01eee'
  pod 'SDWebImage', '5.21.0', :modular_headers => true
  pod 'SDWebImageSwiftUI', '3.1.3', :modular_headers => true
  pod 'Moya', '~> 15.0'
  pod 'SwiftJWT', '3.6.200'
  pod 'TOCropViewController', '2.6.1'
  pod 'lottie-ios', '4.5.2'

  # Debugging purposes
  #  pod 'Reveal-SDK', :configurations => ['Debug']
  
  target 'DashWalletTests' do
    inherit! :search_paths
  end

  target 'DashWalletScreenshotsUITests' do
    inherit! :search_paths
  end

end


target 'TodayExtension' do
  platform :ios, '18.0'

  pod 'DSDynamicOptions', '0.1.2'

end

target 'WatchApp' do
  platform :watchos, '4.0'

end

target 'WatchApp Extension' do
  platform :watchos, '4.0'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|

    # fixes warnings about unsupported Deployment Target in Xcode
    target.build_configurations.each do |config|
      if target.platform_name == :ios
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
      elsif target.platform_name == :watchos
        config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '4.0'
      end

    end

  end

end
