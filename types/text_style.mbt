///|
// Rich text style configuration and expand behavior.
pub(all) enum ExpandType {
  Before
  After
  Both
  NoExpand
} derive(Show, Eq)

///|
pub fn ExpandType::expand_before(self : ExpandType) -> Bool {
  match self {
    ExpandType::Before => true
    ExpandType::Both => true
    _ => false
  }
}

///|
pub fn ExpandType::expand_after(self : ExpandType) -> Bool {
  match self {
    ExpandType::After => true
    ExpandType::Both => true
    _ => false
  }
}

///|
pub fn ExpandType::reverse(self : ExpandType) -> ExpandType {
  match self {
    ExpandType::Before => ExpandType::Before
    ExpandType::After => ExpandType::After
    ExpandType::Both => ExpandType::NoExpand
    ExpandType::NoExpand => ExpandType::Both
  }
}

///|
pub fn ExpandType::from_info(info : Int) -> ExpandType {
  let bits = info & 0x6
  match bits {
    2 => ExpandType::Before
    4 => ExpandType::After
    6 => ExpandType::Both
    _ => ExpandType::NoExpand
  }
}

///|
pub fn ExpandType::to_info(self : ExpandType) -> Int {
  let bits = 0x80
  match self {
    ExpandType::NoExpand => bits
    ExpandType::Before => bits | 0x2
    ExpandType::After => bits | 0x4
    ExpandType::Both => bits | 0x6
  }
}

///|
pub struct StyleConfig {
  expand : ExpandType
} derive(Show, Eq)

///|
pub fn StyleConfig::new() -> StyleConfig {
  StyleConfig::{ expand: ExpandType::NoExpand }
}

///|
pub fn StyleConfig::with_expand(expand : ExpandType) -> StyleConfig {
  StyleConfig::{ expand, }
}

///|
pub struct StyleConfigMap {
  map : Map[String, StyleConfig]
  mut default_style : StyleConfig?
} derive(Show)

///|
pub fn StyleConfigMap::new() -> StyleConfigMap {
  StyleConfigMap::{ map: Map::new(), default_style: None }
}

///|
pub fn StyleConfigMap::default_rich_text_config() -> StyleConfigMap {
  let config = StyleConfigMap::new()
  config.insert("bold", StyleConfig::with_expand(ExpandType::After))
  config.insert("italic", StyleConfig::with_expand(ExpandType::After))
  config.insert("underline", StyleConfig::with_expand(ExpandType::After))
  config.insert("link", StyleConfig::with_expand(ExpandType::NoExpand))
  config.insert("highlight", StyleConfig::with_expand(ExpandType::NoExpand))
  config.insert("comment", StyleConfig::with_expand(ExpandType::NoExpand))
  config.insert("code", StyleConfig::with_expand(ExpandType::NoExpand))
  config
}

///|
pub fn StyleConfigMap::insert(
  self : StyleConfigMap,
  key : String,
  value : StyleConfig,
) -> Unit {
  self.map[key] = value
}

///|
pub fn StyleConfigMap::set_default(
  self : StyleConfigMap,
  value : StyleConfig?,
) -> Unit {
  self.default_style = value
}

///|
pub fn StyleConfigMap::get(self : StyleConfigMap, key : String) -> StyleConfig? {
  let lookup = style_key_root(key)
  match self.map.get(lookup) {
    Some(value) => Some(value)
    None => self.default_style
  }
}

///|
pub fn StyleConfigMap::style_info(
  self : StyleConfigMap,
  key : String,
  is_unmark : Bool,
) -> Int? {
  match self.get(key) {
    Some(config) => {
      let expand = if is_unmark {
        config.expand.reverse()
      } else {
        config.expand
      }
      Some(expand.to_info())
    }
    None => None
  }
}

///|
fn style_key_root(key : String) -> String {
  match key.find(":") {
    Some(idx) => {
      let sb = StringBuilder::new()
      let mut i = 0
      for ch in key {
        if i == idx {
          break
        }
        sb.write_char(ch)
        i = i + 1
      }
      sb.to_string()
    }
    None => key
  }
}
