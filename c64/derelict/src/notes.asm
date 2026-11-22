// Turns tune text into player bytes at assembly time (see music.asm).
// Bytes: note (0 = rest, 1-96) + length in rows; $fe n = instrument n;
// $fd = stop (one-shot tunes, the word "end"); $ff = back to the start.

.function noteNumber(name) {
    .var semis = Hashtable().put("c",0,"d",2,"e",4,"f",5,"g",7,"a",9,"b",11,
                                 "C",0,"D",2,"E",4,"F",5,"G",7,"A",9,"B",11)
    .var letter = name.substring(0, 1)
    .if (!semis.containsKey(letter)) .error "not a note: " + name
    .var semi = semis.get(letter)
    .var rest = name.substring(1, name.size())
    .if (rest.size() > 0 && rest.substring(0, 1) == "#") {
        .eval semi = semi + 1
        .eval rest = rest.substring(1, rest.size())
    }
    .if (rest.size() == 0) .error "note needs an octave: " + name
    .return rest.asNumber() * 12 + semi + 1
}

.function tuneToken(out, tok) {
    .if (tok == "|") .return out
    .if (tok == "end") {
        .eval out.add($fd)
        .return out
    }
    .if (tok.substring(0, 1) == "@") {
        .eval out.add($fe, tok.substring(1, tok.size()).asNumber())
        .return out
    }
    .var name = tok
    .var len = 1
    .for (var i=0; i<tok.size(); i++) {
        .if (tok.substring(i, i+1) == ":") {
            .eval name = tok.substring(0, i)
            .eval len = tok.substring(i+1, tok.size()).asNumber()
        }
    }
    .if (len < 1 || len > 42) .error "length must be 1-42 rows: " + tok
    .var note = 0
    .if (name != "r" && name != "R") .eval note = noteNumber(name)
    .eval out.add(note, len)
    .return out
}

.macro Voice(text) {
    .var out = List()
    .var tok = ""
    .for (var i=0; i<=text.size(); i++) {
        .var c = " "
        .if (i < text.size()) .eval c = text.substring(i, i+1)
        .if (c == " ") {
            .if (tok != "") .eval tuneToken(out, tok)
            .eval tok = ""
        } else {
            .eval tok = tok + c
        }
    }
    .for (var i=0; i<out.size(); i++) .byte out.get(i)
    .byte $ff
}
