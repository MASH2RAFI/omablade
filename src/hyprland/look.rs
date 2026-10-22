use super::hypr_query;
use serde_json::{Map, Value, json};

const OPTIONS: [(&str, &str); 8] = [
    ("rounding", "decoration:rounding"),
    ("borderSize", "general:border_size"),
    ("gapsOut", "general:gaps_out"),
    ("activeBorder", "general:col.active_border"),
    ("inactiveBorder", "general:col.inactive_border"),
    ("activeOpacity", "decoration:active_opacity"),
    ("inactiveOpacity", "decoration:inactive_opacity"),
    ("animations", "animations:enabled"),
];

fn number(option: &Value) -> Option<Value> {
    option
        .get("int")
        .or_else(|| option.get("float"))
        .filter(|value| value.is_number())
        .cloned()
}

fn gaps(option: &Value) -> Option<Value> {
    let numbers: Vec<i64> = option
        .get("css")
        .or_else(|| option.get("custom"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .split_whitespace()
        .filter_map(|part| part.parse::<f64>().ok())
        .map(|value| value.round().max(0.0) as i64)
        .collect();
    let [top, right, bottom, left] = match numbers.as_slice() {
        [all] => [*all; 4],
        [vertical, horizontal] => [*vertical, *horizontal, *vertical, *horizontal],
        [top, right, bottom, left, ..] => [*top, *right, *bottom, *left],
        _ => {
            let all = option.get("int").and_then(Value::as_i64)?.max(0);
            [all; 4]
        }
    };
    Some(json!({"top": top, "right": right, "bottom": bottom, "left": left}))
}

fn gradient(option: &Value) -> Option<Value> {
    option
        .get("gradient")
        .or_else(|| option.get("custom"))
        .or_else(|| option.get("str"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(|text| Value::String(text.to_string()))
}

pub fn look() -> Value {
    let mut result = Map::new();
    result.insert("ok".into(), Value::Bool(true));
    for (key, name) in OPTIONS {
        let Ok(option) = hypr_query(&format!("getoption {name}")) else {
            continue;
        };
        let value = match key {
            "gapsOut" => gaps(&option),
            "activeBorder" | "inactiveBorder" => gradient(&option),
            "animations" => option
                .get("int")
                .and_then(Value::as_i64)
                .map(|value| Value::Bool(value != 0))
                .or_else(|| {
                    option
                        .get("bool")
                        .filter(|value| value.is_boolean())
                        .cloned()
                }),
            _ => number(&option),
        };
        if let Some(value) = value {
            result.insert(key.into(), value);
        }
    }
    Value::Object(result)
}
