.pragma library

function parse(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null
    var parts = value.split("-")
    var date = new Date(0)
    date.setHours(12, 0, 0, 0)
    date.setFullYear(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    return key(date) === value ? date : null
}

function key(date) { return Qt.formatDate(date, "yyyy-MM-dd") }
function label(value, emptyLabel) {
    var date = parse(value)
    return date ? Qt.formatDate(date, "ddd, MMM d, yyyy") : (emptyLabel || "Unscheduled")
}
