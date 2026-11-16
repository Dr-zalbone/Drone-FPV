class_name Attribution
extends RefCounted
## Parses "<title>_attribution-<author>_on_<site>" file names.
## Mirrors parse_attribution() in tools/process_models.py.


static func parse(file_name: String) -> Dictionary:
	var stem := file_name.get_file().get_basename()
	var re := RegEx.create_from_string("^(?<title>.+?)_attrib\\w*?-(?<author>.+?)_on_(?<site>[A-Za-z0-9]+)$")
	var m := re.search(stem)
	if m == null:
		return {}
	return {
		"title": prettify(m.get_string("title")),
		"author": m.get_string("author").replace("_", " ").strip_edges(),
		"site": m.get_string("site").capitalize(),
	}


static func prettify(text: String) -> String:
	var re_sep := RegEx.create_from_string("[_\\.]+")
	text = re_sep.sub(text, " ", true)
	text = RegEx.create_from_string("\\s*-\\s*").sub(text, " - ", true)
	text = RegEx.create_from_string("\\s+").sub(text, " ", true)
	text = text.strip_edges().trim_prefix("-").trim_suffix("-").strip_edges()
	var words := text.split(" ")
	for i in words.size():
		if words[i].length() > 0:
			words[i] = words[i].substr(0, 1).to_upper() + words[i].substr(1).to_lower()
	return " ".join(words)


static func format_line(entry: Dictionary) -> String:
	return "\"%s\" by %s (%s)" % [entry.get("title", "?"), entry.get("author", "?"), entry.get("site", "?")]
