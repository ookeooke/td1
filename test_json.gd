extends SceneTree

func _init():
    var raw = '{"tower_overrides": {"archer": {"l1": {"damage_mult": 1.5}}}}'
    var parsed = JSON.parse_string(raw)
    var cached = {}
    for k in parsed.keys():
        cached[k] = parsed[k]
        
    var t: Dictionary = cached.get("tower_overrides", {})
    var per_tower: Dictionary = t.get("archer", {})
    var per_tier: Dictionary = per_tower.get("l1", {})
    print("Value before write: ", per_tier.get("damage_mult", 1.0))
    
    if not t.has("archer"): t["archer"] = {}
    if not t["archer"].has("l1"): t["archer"]["l1"] = {}
    t["archer"]["l1"]["damage_mult"] = 2.0
    
    print("JSON: ", JSON.stringify(cached, "  "))
    quit()
