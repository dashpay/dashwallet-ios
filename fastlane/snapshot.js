#import "SnapshotHelper.js"

var target = UIATarget.localTarget();
var app = target.frontMostApp();
var window = app.mainWindow();

target.delay(0.5);
captureLocalizedScreenshot('0-new');

target.tap({x:100, y:50});
target.delay(0.5);
captureLocalizedScreenshot('0-splash');

target.tap({x:100, y:50});
target.delay(0.5);
captureLocalizedScreenshot('0-receive');

window.pageIndicators()[0].tap();
target.delay(0.5);
captureLocalizedScreenshot('0-send');

app.navigationBar().buttons()[0].tap();
target.delay(0.5);
captureLocalizedScreenshot('0-history');
