use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Tile { pub id: String, pub columns: u8, pub rows: u8 }
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Layouts { pub system: Vec<Tile>, pub actions: Vec<Tile> }
#[derive(Clone, Debug, Serialize)]
pub struct Placement { pub id: String, pub column: u8, pub row: u8, pub columns: u8, pub rows: u8 }
#[derive(Serialize)]
pub struct ResultLayout { pub tiles: Vec<Tile>, pub placements: Vec<Placement>, pub rows: u8 }
#[derive(Deserialize)]
#[serde(tag="op", rename_all="snake_case", deny_unknown_fields)]
pub enum Request {
    Pack { tiles: Vec<Tile> },
    Resize { tiles: Vec<Tile>, id: String, columns: u8, rows: u8 },
    Move { tiles: Vec<Tile>, from: String, to: String },
}
impl Default for Layouts {
    fn default() -> Self {
        Self { system: (0..2).map(|i| Tile { id: format!("device:{i}"), columns: 3, rows: 2 })
            .chain([Tile { id: "media:0".into(), columns: 6, rows: 2 }]).collect(),
            actions: (0..9).map(|i| Tile { id: format!("app:{i}"), columns: 2, rows: 1 }).collect() }
    }
}
fn minimum(tile: &Tile) -> (u8,u8) { if tile.id.starts_with("device:") { (2,2) } else { (1,1) } }
fn valid(tiles: &[Tile]) -> Result<(),String> {
    if tiles.len()>24 { return Err("Invalid layout length".into()); }
    let mut seen=std::collections::HashSet::new();
    for tile in tiles {
        let (width,height)=minimum(tile);
        if !seen.insert(&tile.id) || tile.id.len()>32 || tile.columns<width || tile.columns>6 || tile.rows<height || tile.rows>4 {
            return Err("Invalid tile size or identity".into());
        }
    }
    Ok(())
}
pub fn pack(tiles: &[Tile]) -> Option<Vec<Placement>> {
    let mut occupied=[[false;6];4]; let mut placements=Vec::new();
    for tile in tiles {
        if tile.columns==0 || tile.columns>6 || tile.rows==0 || tile.rows>4 { return None; }
        let mut position=None;
        'find: for row in 0..=4-tile.rows { for column in 0..=6-tile.columns {
            if (row..row+tile.rows).all(|y| (column..column+tile.columns).all(|x| !occupied[y as usize][x as usize])) {
                position=Some((column,row)); break 'find;
            }
        }}
        let (column,row)=position?;
        for y in row..row+tile.rows { for x in column..column+tile.columns { occupied[y as usize][x as usize]=true; }}
        placements.push(Placement { id:tile.id.clone(), column,row,columns:tile.columns,rows:tile.rows });
    }
    Some(placements)
}
fn shrink(tile: &mut Tile) -> bool {
    let (width,height)=minimum(tile);
    if tile.columns>width && (tile.columns>=tile.rows || tile.rows==height) { tile.columns-=1; true }
    else if tile.rows>height { tile.rows-=1; true }
    else { false }
}
fn resolve(mut tiles: Vec<Tile>, preferred: Option<&str>) -> Result<ResultLayout,String> {
    valid(&tiles)?;
    for _ in 0..128 {
        if let Some(placements)=pack(&tiles) {
            let rows=placements.iter().map(|p|p.row+p.rows).max().unwrap_or(1);
            return Ok(ResultLayout {tiles,placements,rows});
        }
        let candidate=tiles.iter().enumerate().filter(|(_,t)| Some(t.id.as_str())!=preferred && (t.columns,t.rows)!=minimum(t))
            .max_by_key(|(_,t)| t.columns as u16*t.rows as u16).map(|(i,_)|i);
        if let Some(index)=candidate { shrink(&mut tiles[index]); }
        else if let Some(index)=tiles.iter().position(|t|Some(t.id.as_str())==preferred) {
            if !shrink(&mut tiles[index]) { break; }
        } else { break; }
    }
    Err("Layout cannot fit".into())
}
pub fn execute(request: Request) -> Result<ResultLayout,String> {
    match request {
        Request::Pack { tiles } => {
            valid(&tiles)?;
            let placements=pack(&tiles).ok_or("Layout exceeds the page")?;
            let rows=placements.iter().map(|p|p.row+p.rows).max().unwrap_or(1);
            Ok(ResultLayout {tiles,placements,rows})
        }
        Request::Resize { mut tiles,id,columns,rows } => {
            valid(&tiles)?;
            let tile=tiles.iter_mut().find(|t|t.id==id).ok_or("Unknown tile")?;
            let (width,height)=minimum(tile);
            tile.columns=columns.clamp(width,6); tile.rows=rows.clamp(height,4);
            resolve(tiles,Some(&id))
        }
        Request::Move { mut tiles,from,to } => {
            valid(&tiles)?;
            let source=tiles.iter().position(|t|t.id==from).ok_or("Unknown source")?;
            let target=tiles.iter().position(|t|t.id==to).ok_or("Unknown target")?;
            let tile=tiles.remove(source); tiles.insert(target,tile);
            resolve(tiles,Some(&from))
        }
    }
}
impl Layouts {
    pub fn validate(&self, media_count: usize, app_count: usize) -> Result<(),String> {
        for (tiles,prefix,count) in [(&self.system,"media",media_count),(&self.actions,"app",app_count)] {
            valid(tiles)?;
            let actual:std::collections::HashSet<_>=tiles.iter().filter(|t|!t.id.starts_with("device:")).map(|t|t.id.clone()).collect();
            let expected:std::collections::HashSet<_>=(0..count).map(|i|format!("{prefix}:{i}")).collect();
            if actual!=expected || tiles.iter().any(|t|t.id.starts_with("device:") && t.id!="device:0" && t.id!="device:1") || pack(tiles).is_none() {
                return Err("Invalid page layout".into());
            }
        }
        Ok(())
    }
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn resizing_reflows_neighbors_without_overlap() {
        let initial=Layouts::default().actions;
        let result=execute(Request::Resize { tiles:initial.clone(),id:"app:0".into(),columns:6,rows:3 }).unwrap();
        assert_eq!(result.tiles.len(),9); assert!(result.rows<=4);
        assert_ne!(result.tiles,initial);
        for (i,a) in result.placements.iter().enumerate() { for b in &result.placements[i+1..] {
            assert!(a.column+a.columns<=b.column || b.column+b.columns<=a.column || a.row+a.rows<=b.row || b.row+b.rows<=a.row);
        }}
        assert!(result.tiles.iter().skip(1).any(|t|t.columns<2));
    }
    #[test] fn move_preserves_identity_and_reorders() {
        let result=execute(Request::Move { tiles:Layouts::default().system,from:"media:0".into(),to:"device:0".into() }).unwrap();
        assert_eq!(result.tiles[0].id,"media:0"); assert_eq!(result.tiles.len(),3);
        Layouts { system:result.tiles,actions:Layouts::default().actions }.validate(1,9).unwrap();
    }
    #[test] fn oversized_slider_is_clamped_and_legacy_defaults_fit() {
        Layouts::default().validate(1,9).unwrap();
        let result=execute(Request::Resize { tiles:Layouts::default().system,id:"device:0".into(),columns:255,rows:255 }).unwrap();
        assert!(result.rows<=4); assert!(pack(&result.tiles).is_some());
        for tile in &result.tiles { let (w,h)=minimum(tile); assert!(tile.columns>=w && tile.rows>=h); }
    }
}
