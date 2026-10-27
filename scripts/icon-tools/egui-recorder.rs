// Minimal drawing recorder for the original LightCraft icon source. Build tooling only.
mod egui {
    #[derive(Clone, Copy)] pub struct Color32(pub f32);
    impl Color32 { pub fn gamma_multiply(self, a:f32)->Self { Self(self.0*a) } }
    #[derive(Clone, Copy)] pub struct Pos2 { pub x:f32, pub y:f32 }
    pub fn pos2(x:f32,y:f32)->Pos2 { Pos2{x,y} }
    pub fn vec2(x:f32,y:f32)->Pos2 { pos2(x,y) }
    #[derive(Clone, Copy)] pub struct Rect { pub min:Pos2, pub max:Pos2 }
    impl Rect {
        pub fn from_min_max(min:Pos2,max:Pos2)->Self {Self{min,max}}
        pub fn from_center_size(c:Pos2,s:Pos2)->Self {Self{min:pos2(c.x-s.x/2.,c.y-s.y/2.),max:pos2(c.x+s.x/2.,c.y+s.y/2.)}}
        pub fn width(self)->f32 {self.max.x-self.min.x}
        pub fn height(self)->f32 {self.max.y-self.min.y}
        pub fn center(self)->Pos2 {pos2((self.min.x+self.max.x)/2.,(self.min.y+self.max.y)/2.)}
    }
    #[derive(Clone, Copy)] pub struct Stroke {pub width:f32,pub color:Color32}
    impl Stroke { pub const NONE:Self=Self{width:0.,color:Color32(0.)}; pub fn new(width:f32,color:Color32)->Self {Self{width,color}} }
    pub enum StrokeKind {Middle}
    pub struct Shape;
    fn path(pts:Vec<Pos2>,s:Stroke,fill:bool,closed:bool) {
        print!("{{\"kind\":\"path\",\"width\":{},\"alpha\":{},\"fill\":{},\"closed\":{},\"points\":[",s.width,s.color.0,fill,closed);
        for (i,p) in pts.iter().enumerate() {if i>0 {print!(",");} print!("[{},{}]",p.x,p.y);}
        println!("]}}");
    }
    impl Shape {
        pub fn line(p:Vec<Pos2>,s:Stroke)->Self {path(p,s,false,false);Self}
        pub fn closed_line(p:Vec<Pos2>,s:Stroke)->Self {path(p,s,false,true);Self}
        pub fn convex_polygon(p:Vec<Pos2>,c:Color32,_s:Stroke)->Self {path(p,Stroke::new(0.,c),true,true);Self}
    }
    pub struct Painter;
    impl Painter {
        pub fn add(&self,_s:Shape) {}
        pub fn circle_stroke(&self,p:Pos2,r:f32,s:Stroke) {println!("{{\"kind\":\"circle\",\"x\":{},\"y\":{},\"r\":{},\"width\":{},\"alpha\":{},\"fill\":false}}",p.x,p.y,r,s.width,s.color.0);}
        pub fn circle_filled(&self,p:Pos2,r:f32,c:Color32) {println!("{{\"kind\":\"circle\",\"x\":{},\"y\":{},\"r\":{},\"width\":0,\"alpha\":{},\"fill\":true}}",p.x,p.y,r,c.0);}
        pub fn rect_stroke(&self,r:Rect,round:f32,s:Stroke,_k:StrokeKind) {self.rect(r,round,s,false);}
        pub fn rect_filled(&self,r:Rect,round:f32,c:Color32) {self.rect(r,round,Stroke::new(0.,c),true);}
        fn rect(&self,r:Rect,round:f32,s:Stroke,fill:bool) {println!("{{\"kind\":\"rect\",\"x\":{},\"y\":{},\"w\":{},\"h\":{},\"round\":{},\"width\":{},\"alpha\":{},\"fill\":{}}}",r.min.x,r.min.y,r.width(),r.height(),round,s.width,s.color.0,fill);}
        pub fn line_segment(&self,p:[Pos2;2],s:Stroke) {path(p.to_vec(),s,false,false);}
    }
}
