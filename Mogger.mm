// Mogger.mm — Standoff 2 / STANDLEO cheat

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <cmath>

namespace off {
    constexpr uint64_t dwEntityList      = 0x1A1B4C0;
    constexpr uint64_t dwLocalPlayerPawn = 0x1873C20;
    constexpr uint64_t dwViewMatrix      = 0x1A93B40;

    constexpr uint64_t m_iHealth         = 0x344;
    constexpr uint64_t m_iArmor          = 0x348;
    constexpr uint64_t m_iTeamNum        = 0x3D4;
    constexpr uint64_t m_lifeState       = 0x338;
    constexpr uint64_t m_vOldOrigin      = 0x13A0;
    constexpr uint64_t m_vecViewOffset   = 0xE00;
    constexpr uint64_t m_hPlayerPawn     = 0x7EC;
    constexpr uint64_t m_bDormant        = 0x10C;
    constexpr uint64_t m_aimPunchAngle   = 0x1730;
    constexpr uint64_t m_iIDEntIndex     = 0x36BC;
    constexpr uint64_t m_fFlags          = 0x3F8;
    constexpr uint64_t m_nButtons         = 0x1738;
    constexpr uint64_t m_hObserverTarget = 0x1E58;

    constexpr uint64_t m_viewPitch       = 0x1DC;
    constexpr uint64_t m_viewYaw         = 0x1E0;

    constexpr uint64_t off_head          = 0x13A0 + 0x48;
    constexpr uint64_t off_neck          = 0x13A0 + 0x30;
    constexpr uint64_t off_chest         = 0x13A0 + 0x10;
    constexpr uint64_t off_pelvis        = 0x13A0 - 0x10;
    constexpr uint64_t off_legL          = 0x13A0 - 0x50;
    constexpr uint64_t off_legR          = 0x13A0 - 0x48;
    constexpr uint64_t off_armL          = 0x13A0 + 0x28;
    constexpr uint64_t off_armR          = 0x13A0 + 0x20;

    constexpr uint64_t dwPlantedC4       = 0x1A5E0F8;
}

struct Vec3 { float x, y, z; };
struct Vec2 { float x, y; };

static inline Vec3 v3sub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline float v3len(Vec3 v) { return sqrtf(v.x*v.x + v.y*v.y + v.z*v.z); }

static bool worldToScreen(Vec3 w, const float* m, int sw, int sh, Vec2& out) {
    float cx = m[0]*w.x + m[4]*w.y + m[8]*w.z  + m[12];
    float cy = m[1]*w.x + m[5]*w.y + m[9]*w.z  + m[13];
    float cw = m[3]*w.x + m[7]*w.y + m[11]*w.z + m[15];
    if (cw < 0.01f) return false;
    out.x = (sw * 0.5f) * (1.f + cx/cw);
    out.y = (sh * 0.5f) * (1.f - cy/cw);
    return true;
}

template<typename T>
static T rd(uint64_t addr) {
    T v{};
    vm_size_t sz = sizeof(T);
    vm_address_t local = 0;
    if (vm_read(mach_task_self(), addr, sizeof(T), &local, &sz) == KERN_SUCCESS) {
        memcpy(&v, (void*)local, sizeof(T));
        vm_deallocate(mach_task_self(), local, sz);
    }
    return v;
}

template<typename T>
static bool wr(uint64_t addr, T val) {
    return vm_write(mach_task_self(), addr, (vm_address_t)&val, sizeof(T)) == KERN_SUCCESS;
}

static uint64_t getEntity(uint64_t listBase, int idx) {
    uint64_t chunk = rd<uint64_t>(listBase + 0x8 * ((idx & 0x7FFF) >> 9) + 0x10);
    if (!chunk) return 0;
    return rd<uint64_t>(chunk + 0x78 * (idx & 0x1FF));
}

static struct {
    bool esp = true;
    bool filled = false;
    bool hpbar = true;
    bool radar = false;
    bool bomb = true;
    bool aimbot = false;
    bool trigger = false;
    bool bhop = false;
    bool spectators = false;
    float fov = 8.f;
    float smooth = 10.f;
    int bone = 0;
    uint64_t gameBase = 0;
} g_cfg;

struct PlayerInfo {
    uint64_t pawn;
    Vec3 origin, head, neck, chest, pelvis, legL, legR, armL, armR;
    int hp, armor, team;
    float dist;
    bool valid;
};

static int g_localTeam = 0;
static Vec3 g_eye = {0,0,0};
static float g_vm[16] = {0};

static bool collectPlayers(PlayerInfo* out, int maxOut, int& count) {
    count = 0;
    uint64_t client = g_cfg.gameBase;
    if (!client) return false;
    uint64_t lp = rd<uint64_t>(client + off::dwLocalPlayerPawn);
    if (!lp) return false;
    g_localTeam = rd<int>(lp + off::m_iTeamNum);
    Vec3 lpPos = rd<Vec3>(lp + off::m_vOldOrigin);
    Vec3 vOff = rd<Vec3>(lp + off::m_vecViewOffset);
    g_eye = {lpPos.x + vOff.x, lpPos.y + vOff.y, lpPos.z + vOff.z};

    vm_size_t vmsz = sizeof(g_vm);
    vm_address_t local = 0;
    if (vm_read(mach_task_self(), client + off::dwViewMatrix, sizeof(g_vm), &local, &vmsz) == KERN_SUCCESS) {
        memcpy(g_vm, (void*)local, sizeof(g_vm));
        vm_deallocate(mach_task_self(), local, vmsz);
    }

    uint64_t listBase = client + off::dwEntityList;
    for (int i = 1; i <= 64 && count < maxOut; i++) {
        uint64_t ctrl = getEntity(listBase, i);
        if (!ctrl) continue;
        uint64_t pawnH = rd<uint64_t>(ctrl + off::m_hPlayerPawn);
        if (!pawnH) continue;
        uint64_t pawn = getEntity(listBase, (int)(pawnH & 0x7FFF));
        if (!pawn) continue;
        if (rd<bool>(pawn + off::m_bDormant)) continue;
        int hp = rd<int>(pawn + off::m_iHealth);
        if (hp <= 0 || hp > 100) continue;
        int team = rd<int>(pawn + off::m_iTeamNum);
        if (team == g_localTeam) continue;

        PlayerInfo& p = out[count];
        p.pawn = pawn;
        p.hp = hp;
        p.armor = rd<int>(pawn + off::m_iArmor);
        p.team = team;
        p.origin = rd<Vec3>(pawn + off::m_vOldOrigin);
        p.head = rd<Vec3>(pawn + off::off_head);
        p.neck = rd<Vec3>(pawn + off::off_neck);
        p.chest = rd<Vec3>(pawn + off::off_chest);
        p.pelvis = rd<Vec3>(pawn + off::off_pelvis);
        p.legL = rd<Vec3>(pawn + off::off_legL);
        p.legR = rd<Vec3>(pawn + off::off_legR);
        p.armL = rd<Vec3>(pawn + off::off_armL);
        p.armR = rd<Vec3>(pawn + off::off_armR);
        p.dist = v3len(v3sub(p.origin, lpPos));
        p.valid = true;
        count++;
    }
    return count > 0;
}

@interface MoggerESPView : UIView
@end

@implementation MoggerESPView

- (instancetype)initWithFrame:(CGRect)frame base:(uint64_t)base {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        g_cfg.gameBase = base;
        [NSTimer scheduledTimerWithTimeInterval:0.001 target:self
            selector:@selector(tick) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)tick { [self setNeedsDisplay]; }

static void drawSkeleton(CGContextRef ctx, PlayerInfo& p, CGSize size, UIColor* col) {
    Vec2 s[8]; bool ok = true;
    Vec3 bs[8] = {p.head, p.neck, p.chest, p.pelvis, p.legL, p.legR, p.armL, p.armR};
    for (int i = 0; i < 8; i++) {
        if (!worldToScreen(bs[i], g_vm, size.width, size.height, s[i])) { ok = false; break; }
    }
    if (!ok) return;

    CGContextSetStrokeColorWithColor(ctx, col.CGColor);
    CGContextSetLineWidth(ctx, 1.8);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextMoveToPoint(ctx, s[0].x, s[0].y);
    CGContextAddLineToPoint(ctx, s[1].x, s[1].y);
    CGContextAddLineToPoint(ctx, s[2].x, s[2].y);
    CGContextAddLineToPoint(ctx, s[3].x, s[3].y);
    CGContextMoveToPoint(ctx, s[2].x, s[2].y); CGContextAddLineToPoint(ctx, s[6].x, s[6].y);
    CGContextMoveToPoint(ctx, s[2].x, s[2].y); CGContextAddLineToPoint(ctx, s[7].x, s[7].y);
    CGContextMoveToPoint(ctx, s[3].x, s[3].y); CGContextAddLineToPoint(ctx, s[4].x, s[4].y);
    CGContextMoveToPoint(ctx, s[3].x, s[3].y); CGContextAddLineToPoint(ctx, s[5].x, s[5].y);
    CGContextStrokePath(ctx);

    CGFloat r = 4.0;
    CGContextSetFillColorWithColor(ctx, [col colorWithAlphaComponent:0.35].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(s[0].x-r, s[0].y-r, r*2, r*2));
    CGContextStrokeEllipseInRect(ctx, CGRectMake(s[0].x-r, s[0].y-r, r*2, r*2));
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx || !g_cfg.gameBase) return;
    CGSize size = self.bounds.size;

    PlayerInfo list[64];
    int n = 0;
    if (!collectPlayers(list, 64, n)) return;

    for (int i = 0; i < n; i++) {
        PlayerInfo& p = list[i];
        UIColor* col = (p.team == 2) ? [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]
                                     : [UIColor colorWithRed:0.3 green:0.9 blue:1 alpha:1];

        if (g_cfg.esp) {
            drawSkeleton(ctx, p, size, col);

            Vec2 hp_, ft_;
            Vec3 headTop = p.head; headTop.z += 6.f;
            Vec3 feet = p.origin; feet.z -= 6.f;
            if (worldToScreen(headTop, g_vm, size.width, size.height, hp_) &&
                worldToScreen(feet,   g_vm, size.width, size.height, ft_)) {
                CGFloat h = ft_.y - hp_.y;
                CGFloat w = h * 0.45f;
                CGFloat x = hp_.x - w/2;
                CGFloat y = hp_.y;

                if (g_cfg.filled) {
                    CGContextSetFillColorWithColor(ctx, [col colorWithAlphaComponent:0.15].CGColor);
                    CGContextFillRect(ctx, CGRectMake(x, y, w, h));
                }
                CGContextSetStrokeColorWithColor(ctx, col.CGColor);
                CGContextSetLineWidth(ctx, 1.2);
                CGContextStrokeRect(ctx, CGRectMake(x, y, w, h));

                if (g_cfg.hpbar) {
                    CGFloat bw = 3, bh = h * (p.hp / 100.f);
                    CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
                    CGContextFillRect(ctx, CGRectMake(x - 6, y, bw, h));
                    CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
                    CGContextFillRect(ctx, CGRectMake(x - 6, y + (h - bh), bw, bh));
                    if (p.armor > 0) {
                        CGFloat ah = h * (p.armor / 100.f);
                        CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
                        CGContextFillRect(ctx, CGRectMake(x + w + 3, y, bw, h));
                        CGContextSetFillColorWithColor(ctx, [UIColor cyanColor].CGColor);
                        CGContextFillRect(ctx, CGRectMake(x + w + 3, y + (h - ah), bw, ah));
                    }
                }

                NSString* dt = [NSString stringWithFormat:@"%.0fm", p.dist / 100.f];
                NSDictionary* at = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:9],
                                     NSForegroundColorAttributeName: col};
                [dt drawAtPoint:CGPointMake(x + w/2 - 10, y - 12) withAttributes:at];
            }
        }
    }

    if (g_cfg.bomb) {
        uint64_t bomb = g_cfg.gameBase + off::dwPlantedC4;
        bool planted = rd<bool>(bomb + 0x8);
        if (planted) {
            float blow = rd<float>(bomb + 0x10);
            Vec3 bpos = rd<Vec3>(bomb + 0x20);
            Vec2 sp;
            if (worldToScreen(bpos, g_vm, size.width, size.height, sp)) {
                NSString* txt = [NSString stringWithFormat:@"💣 %.1fs", blow];
                UIFont* f = [UIFont boldSystemFontOfSize:12];
                UIColor* c = (blow < 5) ? [UIColor redColor] : [UIColor yellowColor];
                NSDictionary* attrs = @{NSFontAttributeName: f, NSForegroundColorAttributeName: c};
                [txt drawAtPoint:CGPointMake(sp.x - 30, sp.y - 20) withAttributes:attrs];
            }
        }
    }

    if (g_cfg.radar) {
        CGFloat radarSize = 140;
        CGFloat mx = 20, my = size.height - radarSize - 40;
        CGRect radarRect = CGRectMake(mx, my, radarSize, radarSize);

        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
        CGContextFillEllipseInRect(ctx, radarRect);
        CGContextSetStrokeColorWithColor(ctx, [UIColor cyanColor].CGColor);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokeEllipseInRect(ctx, radarRect);

        CGFloat cx = mx + radarSize/2;
        CGFloat cy = my + radarSize/2;
        CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(cx-3, cy-3, 6, 6));

        for (int i = 0; i < n; i++) {
            PlayerInfo& p = list[i];
            Vec3 d = v3sub(p.origin, g_eye);
            CGFloat scale = 1.0f / 200.f;
            CGFloat px = cx + d.x * scale;
            CGFloat py = cy + d.y * scale;
            if (px < mx || px > mx+radarSize || py < my || py > my+radarSize) continue;
            UIColor* c = (p.team == 2) ? [UIColor redColor] : [UIColor cyanColor];
            CGContextSetFillColorWithColor(ctx, c.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(px-2.5, py-2.5, 5, 5));
        }
    }
}

@end

@interface MoggerAimbot : NSObject
+ (instancetype)shared;
- (void)start;
@end

@implementation MoggerAimbot {
    NSTimer* _t;
}

+ (instancetype)shared {
    static MoggerAimbot* s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [MoggerAimbot new]; });
    return s;
}

- (void)start {
    _t = [NSTimer scheduledTimerWithTimeInterval:0.008 target:self
        selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)tick {
    if (!g_cfg.gameBase) return;

    PlayerInfo snap[64]; int sn = 0;
    collectPlayers(snap, 64, sn);

    if (g_cfg.trigger) {
        uint64_t client = g_cfg.gameBase;
        uint64_t lp = rd<uint64_t>(client + off::dwLocalPlayerPawn);
        if (lp) {
            int idx = rd<int>(lp + off::m_iIDEntIndex);
            if (idx > 0) {
                uint64_t target = getEntity(client + off::dwEntityList, idx);
                if (target) {
                    int hp = rd<int>(target + off::m_iHealth);
                    int team = rd<int>(target + off::m_iTeamNum);
                    if (hp > 0 && team != g_localTeam) {
                        uint64_t buttons = rd<uint64_t>(client + off::m_nButtons);
                        wr<uint64_t>(client + off::m_nButtons, buttons | 0x1);
                    }
                }
            }
        }
    }

    if (g_cfg.bhop) {
        uint64_t client = g_cfg.gameBase;
        uint64_t lp = rd<uint64_t>(client + off::dwLocalPlayerPawn);
        if (lp) {
            int flags = rd<int>(lp + off::m_fFlags);
            if (flags & 0x1) {
                uint64_t buttons = rd<uint64_t>(client + off::m_nButtons);
                wr<uint64_t>(client + off::m_nButtons, buttons | 0x2);
            }
        }
    }

    if (!g_cfg.aimbot) return;
    uint64_t client = g_cfg.gameBase;
    uint64_t lp = rd<uint64_t>(client + off::dwLocalPlayerPawn);
    if (!lp) return;

    Vec3 lpPos = rd<Vec3>(lp + off::m_vOldOrigin);
    Vec3 viewOff = rd<Vec3>(lp + off::m_vecViewOffset);
    Vec3 eye = {lpPos.x + viewOff.x, lpPos.y + viewOff.y, lpPos.z + viewOff.z};
    int localTeam = rd<int>(lp + off::m_iTeamNum);

    uint64_t listBase = client + off::dwEntityList;
    uint64_t bestPawn = 0; float bestAng = g_cfg.fov;
    Vec3 bestTarget = {0,0,0};

    for (int i = 1; i <= 64; i++) {
        uint64_t ctrl = getEntity(listBase, i);
        if (!ctrl) continue;
        uint64_t pawnH = rd<uint64_t>(ctrl + off::m_hPlayerPawn);
        if (!pawnH) continue;
        uint64_t pawn = getEntity(listBase, (int)(pawnH & 0x7FFF));
        if (!pawn) continue;
        if (rd<bool>(pawn + off::m_bDormant)) continue;
        if (rd<int>(pawn + off::m_iHealth) <= 0) continue;
        if (rd<int>(pawn + off::m_iTeamNum) == localTeam) continue;

        uint64_t boff = (g_cfg.bone == 0) ? off::off_head :
                        (g_cfg.bone == 1) ? off::off_neck : off::off_chest;
        Vec3 target = rd<Vec3>(pawn + boff);
        Vec3 d = v3sub(target, eye);
        float hyp = sqrtf(d.x*d.x + d.y*d.y);
        float tPitch = atan2f(d.z, hyp) * 180.f / M_PI;
        float tYaw = atan2f(d.y, d.x) * 180.f / M_PI;
        float curP = rd<float>(client + off::m_viewPitch);
        float curY = rd<float>(client + off::m_viewYaw);
        float a = sqrtf((tPitch-curP)*(tPitch-curP) + (tYaw-curY)*(tYaw-curY));
        if (a < bestAng) { bestAng = a; bestPawn = pawn; bestTarget = target; }
    }

    if (!bestPawn) return;

    Vec3 d = v3sub(bestTarget, eye);
    float hyp = sqrtf(d.x*d.x + d.y*d.y);
    float tPitch = atan2f(d.z, hyp) * 180.f / M_PI;
    float tYaw = atan2f(d.y, d.x) * 180.f / M_PI;
    float curP = rd<float>(client + off::m_viewPitch);
    float curY = rd<float>(client + off::m_viewYaw);

    float dP = tPitch - curP;
    float dY = tYaw - curY;
    while (dP > 180) dP -= 360; while (dP < -180) dP += 360;
    while (dY > 180) dY -= 360; while (dY < -180) dY += 360;

    Vec3 punch = rd<Vec3>(lp + off::m_aimPunchAngle);
    float rcsP = punch.x * 2.f;
    float rcsY = punch.y * 2.f;

    wr<float>(client + off::m_viewPitch, curP + dP / g_cfg.smooth - rcsP);
    wr<float>(client + off::m_viewYaw,   curY + dY / g_cfg.smooth - rcsY);
}

@end

@interface MoggerSpecView : UIView
@end
@implementation MoggerSpecView
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx || !g_cfg.spectators || !g_cfg.gameBase) return;
    uint64_t client = g_cfg.gameBase;
    uint64_t lp = rd<uint64_t>(client + off::dwLocalPlayerPawn);
    if (!lp) return;
    int target = rd<int>(lp + off::m_hObserverTarget);
    NSString* txt = [NSString stringWithFormat:@"spectators: %d", target];
    NSDictionary* at = @{NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium],
                         NSForegroundColorAttributeName: [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:0.9]};
    [txt drawAtPoint:CGPointMake(20, 50) withAttributes:at];
}
@end

@interface MoggerMenuVC : UIViewController
@end

@implementation MoggerMenuVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.96];
    self.view.layer.cornerRadius = 22;
    self.view.layer.borderWidth = 1.5;
    self.view.layer.borderColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:1].CGColor;
    self.view.layer.masksToBounds = YES;

    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(22, 22, 200, 30)];
    title.text = @"MOGGER";
    title.font = [UIFont boldSystemFontOfSize:24];
    title.textColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:1];
    [self.view addSubview:title];

    UILabel* sub = [[UILabel alloc] initWithFrame:CGRectMake(22, 54, 260, 18)];
    sub.text = @"v1.1  ·  STANDLEO";
    sub.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    sub.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    [self.view addSubview:sub];

    UIView* line = [[UIView alloc] initWithFrame:CGRectMake(22, 80, 276, 1)];
    line.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.view addSubview:line];

    CGFloat y = 94;
    [self addSection:@"VISUALS" y:y]; y += 28;
    [self addToggle:@"Skeleton ESP" y:y tag:1 val:g_cfg.esp]; y += 40;
    [self addToggle:@"Filled Box" y:y tag:2 val:g_cfg.filled]; y += 40;
    [self addToggle:@"HP / Armor Bar" y:y tag:3 val:g_cfg.hpbar]; y += 40;
    [self addToggle:@"Radar Hack" y:y tag:4 val:g_cfg.radar]; y += 40;
    [self addToggle:@"Bomb Timer" y:y tag:5 val:g_cfg.bomb]; y += 50;

    [self addSection:@"COMBAT" y:y]; y += 28;
    [self addToggle:@"Aimbot" y:y tag:6 val:g_cfg.aimbot]; y += 40;
    [self addToggle:@"Triggerbot" y:y tag:7 val:g_cfg.trigger]; y += 40;
    [self addSlider:@"FOV" y:y tag:8 min:0.5 max:30 val:g_cfg.fov]; y += 56;
    [self addSlider:@"Smooth" y:y tag:9 min:1 max:30 val:g_cfg.smooth]; y += 56;
    [self addSegmentedBone:y]; y += 44;

    [self addSection:@"MISC" y:y]; y += 28;
    [self addToggle:@"Bunnyhop" y:y tag:10 val:g_cfg.bhop]; y += 40;
    [self addToggle:@"Spectator List" y:y tag:11 val:g_cfg.spectators]; y += 40;
}

- (void)addSection:(NSString*)txt y:(CGFloat)y {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(22, y, 260, 18)];
    l.text = txt;
    l.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightBold];
    l.textColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:0.9];
    [self.view addSubview:l];
}

- (void)addToggle:(NSString*)label y:(CGFloat)y tag:(NSInteger)t val:(bool)v {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(22, y, 200, 30)];
    l.text = label;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.textColor = [UIColor whiteColor];
    [self.view addSubview:l];
    UISwitch* s = [[UISwitch alloc] initWithFrame:CGRectMake(247, y, 51, 30)];
    s.on = v;
    s.tag = t;
    s.onTintColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:1];
    [s addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:s];
}

- (void)toggleChanged:(UISwitch*)s {
    switch (s.tag) {
        case 1: g_cfg.esp = s.isOn; break;
        case 2: g_cfg.filled = s.isOn; break;
        case 3: g_cfg.hpbar = s.isOn; break;
        case 4: g_cfg.radar = s.isOn; break;
        case 5: g_cfg.bomb = s.isOn; break;
        case 6: g_cfg.aimbot = s.isOn; break;
        case 7: g_cfg.trigger = s.isOn; break;
        case 10: g_cfg.bhop = s.isOn; break;
        case 11: g_cfg.spectators = s.isOn; break;
    }
}

- (void)addSlider:(NSString*)label y:(CGFloat)y tag:(NSInteger)t min:(float)mn max:(float)mx val:(float)v {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(22, y, 200, 18)];
    l.text = label;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    [self.view addSubview:l];
    UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(22, y + 20, 276, 30)];
    sl.minimumValue = mn; sl.maximumValue = mx; sl.value = v;
    sl.tag = t; sl.tintColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:1];
    [sl addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:sl];
}

- (void)sliderChanged:(UISlider*)s {
    if (s.tag == 8) g_cfg.fov = s.value;
    if (s.tag == 9) g_cfg.smooth = s.value;
}

- (void)addSegmentedBone:(CGFloat)y {
    UILabel* bl = [[UILabel alloc] initWithFrame:CGRectMake(22, y, 200, 18)];
    bl.text = @"Aimbot Bone";
    bl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    bl.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    [self.view addSubview:bl];
    UISegmentedControl* seg = [[UISegmentedControl alloc] initWithItems:@[@"Head", @"Neck", @"Chest"]];
    seg.frame = CGRectMake(22, y + 22, 276, 32);
    seg.selectedSegmentIndex = g_cfg.bone;
    seg.tintColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:1];
    [seg addTarget:self action:@selector(boneChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:seg];
}

- (void)boneChanged:(UISegmentedControl*)s { g_cfg.bone = (int)s.selectedSegmentIndex; }

@end

static UIWindow* g_win = nil;
static UIWindow* g_menuWin = nil;

@interface MoggerButtonTarget : NSObject
- (void)menuTap;
@end

@implementation MoggerButtonTarget
- (void)menuTap {
    if (!g_menuWin) {
        CGRect f = CGRectMake(20, 100, 320, 560);
        g_menuWin = [[UIWindow alloc] initWithFrame:f];
        g_menuWin.windowLevel = UIWindowLevelAlert + 200;
        g_menuWin.backgroundColor = [UIColor clearColor];
        g_menuWin.rootViewController = [MoggerMenuVC new];
    }
    g_menuWin.hidden = !g_menuWin.hidden;
}
@end

static MoggerButtonTarget* g_btnTarget = nil;

static void bootstrap() {
    uint64_t base = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            base = (uint64_t)_dyld_get_image_header(i);
            break;
        }
    }
    if (!base) base = (uint64_t)_dyld_get_image_header(0);
    g_cfg.gameBase = base;

    dispatch_async(dispatch_get_main_queue(), ^{
        g_win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        g_win.windowLevel = UIWindowLevelAlert + 100;
        g_win.backgroundColor = [UIColor clearColor];
        g_win.rootViewController = [UIViewController new];

        MoggerESPView* esp = [[MoggerESPView alloc] initWithFrame:g_win.bounds base:base];
        [g_win addSubview:esp];

        MoggerSpecView* spec = [[MoggerSpecView alloc] initWithFrame:g_win.bounds];
        spec.backgroundColor = [UIColor clearColor];
        spec.userInteractionEnabled = NO;
        [NSTimer scheduledTimerWithTimeInterval:0.5 target:spec
            selector:@selector(setNeedsDisplay) userInfo:nil repeats:YES];
        [g_win addSubview:spec];

        g_btnTarget = [MoggerButtonTarget new];
        UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, 80, 50, 50);
        btn.layer.cornerRadius = 25;
        btn.backgroundColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:0.95];
        btn.layer.shadowColor = [UIColor colorWithRed:0 green:0.9 blue:1 alpha:1].CGColor;
        btn.layer.shadowRadius = 10;
        btn.layer.shadowOpacity = 0.9;
        [btn setTitle:@"M" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
        [btn addTarget:g_btnTarget action:@selector(menuTap) forControlEvents:UIControlEventTouchUpInside];
        [g_win addSubview:btn];

        [g_win makeKeyAndVisible];
        [MoggerAimbot.shared start];
    });
}

__attribute__((constructor))
static void MoggerInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ bootstrap(); });
}
