platform :ios, '10.0'

inhibit_all_warnings!

target 'dashwallet' do
    pod 'DashSync', :path => '../dashsync-iOS'
    #pod 'DashSync', :git => 'git@github.com:dashevo/dashsync-ios.git', :branch => 'master', :commit => '5398500b14c5b34ca1d68f7dd6610f8c8d31a77c'
end

def extension_pods
    pod 'DashSync/AppExtension', :path => '../dashsync-iOS'
end

target 'WatchApp Extension' do
    extension_pods
end

#target 'TodayExtension' do
#    extension_pods
#end
