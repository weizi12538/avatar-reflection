// AvatarReflection (single file)
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ===== ARPrefs.h =====
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

extern NSString *const ARPrefsDidChangeNotification;

@interface ARPrefs : NSObject
+ (BOOL)enabled;                 // 总开关
+ (void)setEnabled:(BOOL)v;
+ (NSInteger)scope;              // 0 = 仅聊天页头像, 1 = 所有头像
+ (void)setScope:(NSInteger)v;
+ (CGFloat)heightRatio;          // 倒影高度 / 头像高度, 0.2 ~ 1.0, 默认 0.85
+ (void)setHeightRatio:(CGFloat)v;
+ (CGFloat)startAlpha;           // 倒影起始透明度, 0.05 ~ 1.0, 默认 0.4
+ (void)setStartAlpha:(CGFloat)v;
+ (CGFloat)gap;                  // 头像与倒影间距(pt), 0 ~ 12, 默认 0
+ (void)setGap:(CGFloat)v;
+ (NSString *)customClassName;   // 高级: 手动指定头像类名(需重启微信)
+ (void)setCustomClassName:(NSString *)v;
+ (void)resetAll;
@end

// ===== ARReflectionView.h =====
#import <UIKit/UIKit.h>

// 一块"镜像 + 渐隐"的倒影视图: 内容是头像垂直翻转后的位图, 再叠一层从上到下渐隐的 mask。
@interface ARReflectionView : UIView
@property (nonatomic, readonly) BOOL hasContent;
- (void)setSourceImage:(UIImage *)image size:(CGSize)size corner:(CGFloat)corner;
- (void)setRatio:(CGFloat)ratio startAlpha:(CGFloat)alpha;
@end

// ===== ARSettingsViewController.h =====
#import <UIKit/UIKit.h>

// 微信 设置 → "头像倒影" 独立面板
@interface ARSettingsViewController : UITableViewController
@end

// ===== ARPrefs.m =====
NSString *const ARPrefsDidChangeNotification = @"AvatarReflectionPrefsDidChange";

static NSString *const kEnabled = @"AvatarReflection.enabled";
static NSString *const kScope   = @"AvatarReflection.scope";
static NSString *const kRatio   = @"AvatarReflection.ratio";
static NSString *const kAlpha   = @"AvatarReflection.alpha";
static NSString *const kGap     = @"AvatarReflection.gap";
static NSString *const kClass   = @"AvatarReflection.className";

static NSUserDefaults *D(void) { return [NSUserDefaults standardUserDefaults]; }

static CGFloat F(NSString *k, CGFloat def, CGFloat lo, CGFloat hi) {
    id o = [D() objectForKey:k];
    CGFloat v = [o isKindOfClass:[NSNumber class]] ? [o doubleValue] : def;
    return MIN(MAX(v, lo), hi);
}

static void Changed(void) {
    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ARPrefsDidChangeNotification object:nil];
    };
    if ([NSThread isMainThread]) post(); else dispatch_async(dispatch_get_main_queue(), post);
}

@implementation ARPrefs

+ (BOOL)enabled { id o = [D() objectForKey:kEnabled]; return o ? [o boolValue] : YES; }
+ (void)setEnabled:(BOOL)v { [D() setBool:v forKey:kEnabled]; Changed(); }

+ (NSInteger)scope { id o = [D() objectForKey:kScope]; return o ? ([o integerValue] == 1 ? 1 : 0) : 0; }
+ (void)setScope:(NSInteger)v { [D() setInteger:v forKey:kScope]; Changed(); }

+ (CGFloat)heightRatio { return F(kRatio, 0.85, 0.2, 1.0); }
+ (void)setHeightRatio:(CGFloat)v { [D() setDouble:v forKey:kRatio]; Changed(); }

+ (CGFloat)startAlpha { return F(kAlpha, 0.4, 0.05, 1.0); }
+ (void)setStartAlpha:(CGFloat)v { [D() setDouble:v forKey:kAlpha]; Changed(); }

+ (CGFloat)gap { return F(kGap, 0, 0, 12); }
+ (void)setGap:(CGFloat)v { [D() setDouble:v forKey:kGap]; Changed(); }

+ (NSString *)customClassName { return [D() stringForKey:kClass] ?: @""; }
+ (void)setCustomClassName:(NSString *)v {
    NSString *t = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length) [D() setObject:t forKey:kClass]; else [D() removeObjectForKey:kClass];
}

+ (void)resetAll {
    for (NSString *k in @[kEnabled, kScope, kRatio, kAlpha, kGap]) [D() removeObjectForKey:k];
    Changed();
}
@end

// ===== ARReflectionView.m =====
@implementation ARReflectionView {
    CAGradientLayer *_mask;
    UIImage *_src;
    CGSize _srcSize;
    CGFloat _srcCorner;
    CGFloat _ratio, _alpha;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.layer.contentsGravity = kCAGravityResize;
        self.layer.contentsScale = UIScreen.mainScreen.scale;
        _ratio = 0.85; _alpha = 0.4;
        _mask = [CAGradientLayer layer];
        _mask.startPoint = CGPointMake(0.5, 0);
        _mask.endPoint = CGPointMake(0.5, 1);
        _mask.locations = @[@0, @0.5, @1];
        self.layer.mask = _mask;
        [self refreshMask];
    }
    return self;
}

- (BOOL)hasContent { return self.layer.contents != nil; }

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _mask.frame = self.bounds;
    [CATransaction commit];
}

- (void)refreshMask {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _mask.colors = @[
        (id)[UIColor colorWithWhite:1 alpha:_alpha].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:_alpha * 0.35].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:0].CGColor
    ];
    [CATransaction commit];
}

- (void)setRatio:(CGFloat)ratio startAlpha:(CGFloat)alpha {
    _ratio = ratio; _alpha = alpha;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // 翻转后的位图里, 头像最底部在最上面; 只取最上面 ratio 的部分
    self.layer.contentsRect = CGRectMake(0, 0, 1, ratio);
    [CATransaction commit];
    [self refreshMask];
}

- (void)setSourceImage:(UIImage *)image size:(CGSize)size corner:(CGFloat)corner {
    if (image == _src && CGSizeEqualToSize(size, _srcSize) && corner == _srcCorner && self.hasContent) return;
    _src = image; _srcSize = size; _srcCorner = corner;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!image || size.width < 1 || size.height < 1 || image.size.width < 1 || image.size.height < 1) {
        self.layer.contents = nil;
        [CATransaction commit];
        return;
    }
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    UIImage *flipped = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        // 垂直镜像
        CGContextTranslateCTM(c, 0, size.height);
        CGContextScaleCTM(c, 1, -1);
        CGRect rect = (CGRect){CGPointZero, size};
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:corner] addClip];
        // aspect fill
        CGSize is = image.size;
        CGFloat s = MAX(size.width / is.width, size.height / is.height);
        CGSize ds = CGSizeMake(is.width * s, is.height * s);
        [image drawInRect:CGRectMake((size.width - ds.width) / 2, (size.height - ds.height) / 2, ds.width, ds.height)];
    }];
    self.layer.contents = (__bridge id)flipped.CGImage;
    self.layer.contentsScale = flipped.scale;
    self.layer.contentsRect = CGRectMake(0, 0, 1, _ratio);
    [CATransaction commit];
}
@end

// ===== ARSettingsViewController.m =====
@interface ARSettingsViewController () <UITextFieldDelegate>
@end

@implementation ARSettingsViewController {
    NSArray<NSArray<UITableViewCell *> *> *_cells;
    NSArray<NSString *> *_headers;
    NSArray<NSString *> *_footers;
    UISwitch *_sw;
    UISegmentedControl *_seg;
    UISlider *_sH, *_sA, *_sG;
    UILabel *_lH, *_lA, *_lG;
    UITextField *_tf;
    UITableViewCell *_resetCell;
    UIView *_header;
    UIImageView *_pAvatar;
    ARReflectionView *_pRefl;
    UIImage *_pImg;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

#pragma mark - build

- (UITableViewCell *)sliderCell:(NSString *)title slider:(UISlider *)s label:(UILabel *)l {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *t = [UILabel new];
    t.text = title;
    t.font = [UIFont systemFontOfSize:16];
    l.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    l.textColor = UIColor.secondaryLabelColor;
    l.textAlignment = NSTextAlignmentRight;
    [l setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[t, l]];
    top.axis = UILayoutConstraintAxisHorizontal;
    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[top, s]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 8;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [c.contentView addSubview:col];
    UILayoutGuide *g = c.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [col.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:10],
        [col.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-10],
        [col.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [col.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
    ]];
    return c;
}

- (UISlider *)slider:(float)min max:(float)max value:(float)v {
    UISlider *s = [UISlider new];
    s.minimumValue = min; s.maximumValue = max; s.value = v;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"头像倒影";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    // 开关
    _sw = [UISwitch new];
    _sw.on = [ARPrefs enabled];
    [_sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
    UITableViewCell *c0 = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c0.textLabel.text = @"启用头像倒影";
    c0.accessoryView = _sw;
    c0.selectionStyle = UITableViewCellSelectionStyleNone;

    // 范围
    _seg = [[UISegmentedControl alloc] initWithItems:@[@"仅聊天页", @"所有头像"]];
    _seg.selectedSegmentIndex = [ARPrefs scope];
    _seg.frame = CGRectMake(0, 0, 190, 32);
    [_seg addTarget:self action:@selector(segChanged:) forControlEvents:UIControlEventValueChanged];
    UITableViewCell *c1 = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c1.textLabel.text = @"作用范围";
    c1.accessoryView = _seg;
    c1.selectionStyle = UITableViewCellSelectionStyleNone;

    // 滑块
    _sH = [self slider:0.2 max:1.0 value:[ARPrefs heightRatio]];
    _sA = [self slider:0.05 max:1.0 value:[ARPrefs startAlpha]];
    _sG = [self slider:0 max:12 value:[ARPrefs gap]];
    _lH = [UILabel new]; _lA = [UILabel new]; _lG = [UILabel new];
    UITableViewCell *c2 = [self sliderCell:@"倒影高度" slider:_sH label:_lH];
    UITableViewCell *c3 = [self sliderCell:@"起始透明度" slider:_sA label:_lA];
    UITableViewCell *c4 = [self sliderCell:@"与头像间距" slider:_sG label:_lG];

    // 高级: 类名
    _tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 210, 30)];
    _tf.placeholder = @"MMHeadImageView";
    _tf.text = [ARPrefs customClassName];
    _tf.textAlignment = NSTextAlignmentRight;
    _tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _tf.autocorrectionType = UITextAutocorrectionTypeNo;
    _tf.returnKeyType = UIReturnKeyDone;
    _tf.delegate = self;
    UITableViewCell *c5 = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c5.textLabel.text = @"头像类名";
    c5.accessoryView = _tf;
    c5.selectionStyle = UITableViewCellSelectionStyleNone;

    // 重置
    _resetCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    _resetCell.textLabel.text = @"恢复默认设置";
    _resetCell.textLabel.textColor = UIColor.systemRedColor;
    _resetCell.textLabel.textAlignment = NSTextAlignmentCenter;

    _cells = @[@[c0, c1], @[c2, c3, c4], @[c5], @[_resetCell]];
    _headers = @[@"", @"效果", @"高级", @""];
    _footers = @[@"修改后立即生效。\"仅聊天页\"只给聊天消息里的头像加倒影。",
                 @"倒影高度默认 85%，起始透明度默认 40%。",
                 @"只有默认类名无效(开了没效果)时才需要改，修改后请完全退出并重开微信。",
                 @""];

    [self buildPreview];
    [self refreshLabels];
    [self updatePreview];
}

#pragma mark - preview

- (UIImage *)sampleImage {
    CGSize s = CGSizeMake(72, 72);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:s];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        NSArray *cols = @[(id)[UIColor colorWithRed:0.98 green:0.66 blue:0.55 alpha:1].CGColor,
                          (id)[UIColor colorWithRed:0.55 green:0.45 blue:0.90 alpha:1].CGColor];
        CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
        CGContextDrawLinearGradient(c, g, CGPointZero, CGPointMake(s.width, s.height), 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(cs);
        UIImage *p = [[UIImage systemImageNamed:@"person.fill"] imageWithTintColor:UIColor.whiteColor
                                                                    renderingMode:UIImageRenderingModeAlwaysOriginal];
        [p drawInRect:CGRectMake(14, 12, 44, 48)];
    }];
}

- (void)buildPreview {
    CGFloat w = self.view.bounds.size.width;
    _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 192)];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _pImg = [self sampleImage];
    _pAvatar = [[UIImageView alloc] initWithImage:_pImg];
    _pAvatar.frame = CGRectMake((w - 72) / 2, 24, 72, 72);
    _pAvatar.layer.cornerRadius = 8;
    _pAvatar.clipsToBounds = YES;
    _pAvatar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _pRefl = [[ARReflectionView alloc] initWithFrame:CGRectZero];
    _pRefl.autoresizingMask = _pAvatar.autoresizingMask;
    [_header addSubview:_pRefl];
    [_header addSubview:_pAvatar];
    self.tableView.tableHeaderView = _header;
}

- (void)updatePreview {
    CGFloat ratio = [ARPrefs heightRatio], gap = [ARPrefs gap];
    BOOL on = [ARPrefs enabled];
    CGRect af = _pAvatar.frame;
    _pRefl.frame = CGRectMake(af.origin.x, CGRectGetMaxY(af) + gap, 72, floor(72 * ratio));
    [_pRefl setRatio:ratio startAlpha:[ARPrefs startAlpha]];
    [_pRefl setSourceImage:_pImg size:CGSizeMake(72, 72) corner:8];
    _pRefl.hidden = !on;
}

- (void)refreshLabels {
    _lH.text = [NSString stringWithFormat:@"%d%%", (int)lround(_sH.value * 100)];
    _lA.text = [NSString stringWithFormat:@"%d%%", (int)lround(_sA.value * 100)];
    _lG.text = [NSString stringWithFormat:@"%.0f pt", _sG.value];
}

#pragma mark - actions

- (void)swChanged:(UISwitch *)s { [ARPrefs setEnabled:s.on]; [self updatePreview]; }
- (void)segChanged:(UISegmentedControl *)s { [ARPrefs setScope:s.selectedSegmentIndex]; }

- (void)sliderChanged:(UISlider *)s {
    if (s == _sH) [ARPrefs setHeightRatio:s.value];
    else if (s == _sA) [ARPrefs setStartAlpha:s.value];
    else if (s == _sG) [ARPrefs setGap:roundf(s.value)];
    [self refreshLabels];
    [self updatePreview];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)tf { [ARPrefs setCustomClassName:tf.text]; }

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (_cells[ip.section][ip.row] != _resetCell) return;
    [ARPrefs resetAll];
    _sw.on = [ARPrefs enabled];
    _seg.selectedSegmentIndex = [ARPrefs scope];
    _sH.value = [ARPrefs heightRatio];
    _sA.value = [ARPrefs startAlpha];
    _sG.value = [ARPrefs gap];
    [self refreshLabels];
    [self updatePreview];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _cells.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _cells[s].count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip { return _cells[ip.section][ip.row]; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _headers[s].length ? _headers[s] : nil; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return _footers[s].length ? _footers[s] : nil; }
@end

// ===== Tweak.m =====
// AvatarReflection - 微信头像下方"镜像渐隐倒影" + 设置页独立面板
// 纯 Objective-C runtime 实现, 不依赖 CydiaSubstrate, 适合 LCSign / 侧载注入。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
// ---- 头像类名候选(不同微信版本可能不同; 也可在面板"高级"里手动填) ----
static NSArray<NSString *> *ARDefaultAvatarClassNames(void) {
    return @[@"MMHeadImageView"];
}

static const void *kReflKey = &kReflKey;
static Class gAvatarClass;
static NSHashTable<UIView *> *gTracked;

#pragma mark - runtime helpers

static IMP ARHook(Class cls, SEL sel, IMP imp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    IMP orig = method_getImplementation(m);
    // 类自己没实现(继承来的) -> 加一个; 自己实现了 -> 替换
    if (class_addMethod(cls, sel, imp, method_getTypeEncoding(m))) return orig;
    return method_setImplementation(m, imp);
}

static id ARIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    return iv ? object_getIvar(obj, iv) : nil;
}

#pragma mark - avatar helpers

static BOOL ARIsAvatar(UIView *v) {
    return gAvatarClass && [v isKindOfClass:gAvatarClass];
}

static BOOL ARInChat(UIView *v) {
    UIResponder *r = v;
    for (int i = 0; r && i < 16; i++, r = r.nextResponder) {
        NSString *n = NSStringFromClass([r class]);
        if ([n containsString:@"MessageCell"] || [n containsString:@"MsgCell"] ||
            [n containsString:@"BaseMsgContent"] || [n containsString:@"ChatRoomViewController"]) return YES;
    }
    return NO;
}

static BOOL ARShouldShow(UIView *v) {
    if (![ARPrefs enabled] || !v.superview || v.hidden || v.alpha < 0.01) return NO;
    CGSize s = v.bounds.size;
    if (s.width < 20 || s.height < 20) return NO;
    if ([ARPrefs scope] == 0) {
        if (s.width > 80) return NO;
        if (!ARInChat(v)) return NO;
    }
    return YES;
}

static UIImageView *ARFindImageView(UIView *v, CGFloat minW, int depth) {
    if ([v isKindOfClass:[UIImageView class]] && ((UIImageView *)v).image && v.bounds.size.width >= minW) {
        return (UIImageView *)v;
    }
    if (depth > 2) return nil;
    for (UIView *s in v.subviews) {
        UIImageView *r = ARFindImageView(s, minW, depth + 1);
        if (r) return r;
    }
    return nil;
}

static UIImage *ARSnapshot(UIView *v) {
    CGSize s = v.bounds.size;
    if (s.width < 1 || s.height < 1) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:s];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [v.layer renderInContext:ctx.CGContext];
    }];
}

static void ARSync(UIView *avatar) {
    if (![NSThread isMainThread]) return;
    if (!gTracked) gTracked = [NSHashTable weakObjectsHashTable];
    [gTracked addObject:avatar];

    ARReflectionView *rv = objc_getAssociatedObject(avatar, kReflKey);
    if (!ARShouldShow(avatar)) { if (rv) rv.hidden = YES; return; }

    UIView *sup = avatar.superview;
    if (!rv) {
        rv = [[ARReflectionView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(avatar, kReflKey, rv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (rv.superview != sup) [sup insertSubview:rv belowSubview:avatar];

    CGRect f = avatar.frame;
    CGFloat ratio = [ARPrefs heightRatio], gap = [ARPrefs gap];
    rv.frame = CGRectMake(f.origin.x, CGRectGetMaxY(f) + gap, f.size.width, floor(f.size.height * ratio));
    rv.alpha = avatar.alpha;
    rv.hidden = NO;
    [rv setRatio:ratio startAlpha:[ARPrefs startAlpha]];

    UIImageView *iv = ARFindImageView(avatar, f.size.width * 0.6, 0);
    UIImage *img = iv.image;
    CGFloat corner = MAX(avatar.layer.cornerRadius, iv.layer.cornerRadius);
    if (!img && !rv.hasContent) img = ARSnapshot(avatar);   // 兜底: 头像不是 UIImageView 时截图
    if (img) [rv setSourceImage:img size:f.size corner:corner];
}

#pragma mark - avatar hooks

static void (*o_layout)(UIView *, SEL);
static void n_layout(UIView *s, SEL c) { o_layout(s, c); ARSync(s); }

static void (*o_setFrame)(UIView *, SEL, CGRect);
static void n_setFrame(UIView *s, SEL c, CGRect r) { o_setFrame(s, c, r); ARSync(s); }

static void (*o_setCenter)(UIView *, SEL, CGPoint);
static void n_setCenter(UIView *s, SEL c, CGPoint p) { o_setCenter(s, c, p); ARSync(s); }

static void (*o_setHidden)(UIView *, SEL, BOOL);
static void n_setHidden(UIView *s, SEL c, BOOL h) { o_setHidden(s, c, h); ARSync(s); }

static void (*o_setAlpha)(UIView *, SEL, CGFloat);
static void n_setAlpha(UIView *s, SEL c, CGFloat a) { o_setAlpha(s, c, a); ARSync(s); }

static void (*o_didMoveSuper)(UIView *, SEL);
static void n_didMoveSuper(UIView *s, SEL c) { o_didMoveSuper(s, c); ARSync(s); }

static void (*o_didMoveWin)(UIView *, SEL);
static void n_didMoveWin(UIView *s, SEL c) { o_didMoveWin(s, c); ARSync(s); }

static void (*o_willMoveSuper)(UIView *, SEL, UIView *);
static void n_willMoveSuper(UIView *s, SEL c, UIView *n) {
    o_willMoveSuper(s, c, n);
    if (n != s.superview) {   // 换父视图/被移除(cell 复用): 倒影一起撤掉, 之后在 didMoveToSuperview 重建
        ARReflectionView *rv = objc_getAssociatedObject(s, kReflKey);
        [rv removeFromSuperview];
    }
}

// 头像图片异步加载完成时刷新倒影
static void (*o_setImage)(UIImageView *, SEL, UIImage *);
static void n_setImage(UIImageView *s, SEL c, UIImage *img) {
    o_setImage(s, c, img);
    if (!gAvatarClass || ![NSThread isMainThread]) return;
    UIView *v = s;
    for (int i = 0; i < 3 && v; i++, v = v.superview) {
        if (ARIsAvatar(v)) { ARSync(v); break; }
    }
}

#pragma mark - settings entry

static void ar_openPanel(UIViewController *self, SEL _cmd) {
    ARSettingsViewController *vc = [ARSettingsViewController new];
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:vc]
                           animated:YES completion:nil];
    }
}

typedef id   (*Msg0)(id, SEL);
typedef id   (*MsgCell5)(id, SEL, SEL, id, id, id, long long);
typedef id   (*MsgCell4)(id, SEL, SEL, id, id, long long);
typedef id   (*MsgCell3)(id, SEL, SEL, id, id);
typedef void (*MsgV1)(id, SEL, id);
typedef void (*MsgIns)(id, SEL, id, unsigned int);

static BOOL ARInsertSettingsCell(UIViewController *vc) {
    id mgr = ARIvar(vc, "m_tableViewMgr") ?: ARIvar(vc, "m_tableViewInfo");
    if (!mgr) return NO;

    Class secCls  = NSClassFromString(@"WCTableViewSectionManager") ?: NSClassFromString(@"MMTableViewSectionInfo");
    Class cellCls = NSClassFromString(@"WCTableViewNormalCellManager") ?: NSClassFromString(@"MMTableViewCellInfo");
    if (!secCls || !cellCls) return NO;

    SEL secSel = [secCls respondsToSelector:NSSelectorFromString(@"defaultSection")]
                 ? NSSelectorFromString(@"defaultSection") : NSSelectorFromString(@"sectionInfoDefaut");
    if (![secCls respondsToSelector:secSel]) return NO;
    id sec = ((Msg0)objc_msgSend)(secCls, secSel);

    SEL act = @selector(ar_openPanel);
    NSString *title = @"头像倒影";
    id cell = nil;
    SEL s5 = NSSelectorFromString(@"normalCellForSel:target:title:rightValue:accessoryType:");
    SEL s4 = NSSelectorFromString(@"normalCellForSel:target:title:accessoryType:");
    SEL s3 = NSSelectorFromString(@"normalCellForSel:target:title:");
    if ([cellCls respondsToSelector:s5])      cell = ((MsgCell5)objc_msgSend)(cellCls, s5, act, vc, title, @"", 1);
    else if ([cellCls respondsToSelector:s4]) cell = ((MsgCell4)objc_msgSend)(cellCls, s4, act, vc, title, 1);
    else if ([cellCls respondsToSelector:s3]) cell = ((MsgCell3)objc_msgSend)(cellCls, s3, act, vc, title);
    if (!cell || !sec) return NO;

    SEL add = NSSelectorFromString(@"addCell:");
    if (![sec respondsToSelector:add]) return NO;
    ((MsgV1)objc_msgSend)(sec, add, cell);

    SEL ins = NSSelectorFromString(@"insertSection:At:");
    SEL app = NSSelectorFromString(@"addSection:");
    if ([mgr respondsToSelector:ins])      ((MsgIns)objc_msgSend)(mgr, ins, sec, 0);
    else if ([mgr respondsToSelector:app]) ((MsgV1)objc_msgSend)(mgr, app, sec);
    else return NO;

    SEL gtv = NSSelectorFromString(@"getTableView");
    if ([mgr respondsToSelector:gtv]) {
        id tv = ((Msg0)objc_msgSend)(mgr, gtv);
        if ([tv respondsToSelector:@selector(reloadData)]) [tv reloadData];
    }
    return YES;
}

static void (*o_reloadTableData)(UIViewController *, SEL);
static void n_reloadTableData(UIViewController *self, SEL _cmd) {
    o_reloadTableData(self, _cmd);
    BOOL ok = NO;
    @try { ok = ARInsertSettingsCell(self); } @catch (__unused NSException *e) { ok = NO; }
    if (!ok && !self.navigationItem.rightBarButtonItem) {
        // 兜底: 微信内部类结构变了, 就在设置页右上角放一个"倒影"按钮
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"倒影" style:UIBarButtonItemStylePlain
                                            target:self action:@selector(ar_openPanel)];
    }
}

#pragma mark - install

static BOOL gImageHooked, gSettingsHooked;

static void ARInstallAll(void) {
    if (!gImageHooked) {
        gImageHooked = YES;
        o_setImage = (void *)ARHook([UIImageView class], @selector(setImage:), (IMP)n_setImage);
    }

    if (!gAvatarClass) {
        NSMutableArray *names = [NSMutableArray array];
        NSString *custom = [ARPrefs customClassName];
        if (custom.length) [names addObject:custom];
        [names addObjectsFromArray:ARDefaultAvatarClassNames()];
        for (NSString *n in names) {
            Class c = NSClassFromString(n);
            if (c && [c isSubclassOfClass:[UIView class]]) {
                gAvatarClass = c;
                o_layout        = (void *)ARHook(c, @selector(layoutSubviews),        (IMP)n_layout);
                o_setFrame      = (void *)ARHook(c, @selector(setFrame:),             (IMP)n_setFrame);
                o_setCenter     = (void *)ARHook(c, @selector(setCenter:),            (IMP)n_setCenter);
                o_setHidden     = (void *)ARHook(c, @selector(setHidden:),            (IMP)n_setHidden);
                o_setAlpha      = (void *)ARHook(c, @selector(setAlpha:),             (IMP)n_setAlpha);
                o_didMoveSuper  = (void *)ARHook(c, @selector(didMoveToSuperview),    (IMP)n_didMoveSuper);
                o_didMoveWin    = (void *)ARHook(c, @selector(didMoveToWindow),       (IMP)n_didMoveWin);
                o_willMoveSuper = (void *)ARHook(c, @selector(willMoveToSuperview:),  (IMP)n_willMoveSuper);
                break;
            }
        }
    }

    if (!gSettingsHooked) {
        Class s = NSClassFromString(@"NewSettingViewController");
        if (s) {
            gSettingsHooked = YES;
            class_addMethod(s, @selector(ar_openPanel), (IMP)ar_openPanel, "v@:");
            o_reloadTableData = (void *)ARHook(s, NSSelectorFromString(@"reloadTableData"), (IMP)n_reloadTableData);
            if (!o_reloadTableData) gSettingsHooked = NO;
        }
    }
}

__attribute__((constructor)) static void ARInit(void) {
    @autoreleasepool {
        ARInstallAll();
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        // 有的类在启动完成后才注册, 再试一次
        [nc addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
                         queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { ARInstallAll(); }];
        // 面板里改了参数 -> 刷新所有已出现过的头像
        [nc addObserverForName:ARPrefsDidChangeNotification object:nil
                         queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
            for (UIView *v in gTracked.allObjects) ARSync(v);
        }];
    }
}
