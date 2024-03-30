package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"

Line :: struct {
    command: string,
    segment: string,
    index: string
}

Lines_State :: struct {
    lines: [dynamic]string,
    file_data: []byte
}

read_file_by_lines_in_whole :: proc(file_path: string, lines: ^Lines_State) {
    data, ok := os.read_entire_file(file_path, context.allocator)
    if !ok {
        return
    } 
    lines.file_data = data

    it := string(data)
    for line in strings.split_lines_iterator(&it) {
        if line != "" {
            append(&lines.lines, line)
        }
    }
}

parse_files :: proc(lines: ^Lines_State, parse_lines: ^[dynamic]Line) {
    for line in lines.lines {
        if line[0] == '/' {
            continue
        }

        command: string
        segment: string
        index: string
        
        parts := strings.split(line, " ")
        if len(parts) == 1 {
            command = parts[0]    
        }

        if len(parts) == 2 {
            command = parts[0]    
            segment = parts[1]    
        }

        if len(parts) == 3 {
            command = parts[0]    
            segment = parts[1]    
            index = parts[2]    
        }

        new_parsed_line := Line{command, segment, index}

        append(&parse_lines^, new_parsed_line)
    }
}

lines_init :: proc() -> Lines_State {
    return Lines_State{}
}

lines_destroy :: proc(lines_state: ^Lines_State) {
    delete(lines_state.lines)
    delete(lines_state.file_data)
}

process_arithmetic ::proc(line: Line, translated_lines: ^[dynamic]string) {
    m := map[string]string {
        "add" = "+",
        "sub" = "-",
        "and" = "&",
        "or" = "|",
        "neg" = "-",
        "not" = "!",
        "eq" = "JNE",
        "lt" = "JGE",
        "gt" = "JLE",
    }

    if line.command == "neg" || line.command == "not" {
        append(&translated_lines^, "@SP")
        append(&translated_lines^, "A=M-1")
        m_eq_m_blank_d := strings.concatenate({"M=M", m[line.command], "D"}) 
        append(&translated_lines^, m_eq_m_blank_d)
        return
    }
    
    append(&translated_lines^, "@SP")
    append(&translated_lines^, "AM=M-1")
    append(&translated_lines^, "D=M")
    append(&translated_lines^, "A=A-1")

    if line.command == "add" ||
        line.command == "sub" ||
        line.command == "and" ||
        line.command == "or" {
        
        value_to_append := strings.concatenate({"M=M", m[line.command], "D"})
        append(&translated_lines^, value_to_append)
    } else if line.command == "eq" ||
                line.command == "gt" ||
                line.command == "lt" {
        // TODO: eq gr lt
        // append(&translated_lines^, "D=M-D")
        // append(&translated_lines^, "D=M-D")
    } else {
        syntax_error(line.command)
    }
}

syntax_error :: proc(at: string) {
    fmt.println("Syntax error @", at)
    os.exit(-1)
}

process_push_pop :: proc(line: Line, translated_lines: ^[dynamic]string) {

    m := map[string]string {
        "local" = "@LCL",
        "argument" = "@ARG",
        "this" = "@THIS",
        "that" = "@THAT",
        "static" = "16",
        "temp" = "5",
        "pointer" = "3",
    }
    
    if line.segment == "constant" {
        assert(line.command != "pop")
        line_to_append := strings.concatenate({"@", line.index})
        append(&translated_lines^, line_to_append)

    } else if line.segment == "static" {
            // TODO: make static work
            // append(&translated_lines^, line.index)

    } else if line.segment == "temp" || line.segment == "pointer" { 
        assert(strconv.atoi(line.index) <= 10)
        format_value := strings.concatenate({m[line.segment], line.index})
        line_to_append := strings.concatenate({"@R", format_value})
        append(&translated_lines^, line_to_append)

    } else if line.segment == "local" ||
              line.segment == "argument" ||
              line.segment == "this" ||
              line.segment == "that" {
        arg1 := m[line.segment]
        arg2 := strings.concatenate({"@", line.index})
        append(&translated_lines^, arg1)
        append(&translated_lines^, "D=M")
        append(&translated_lines^, arg2)
        append(&translated_lines^, "A=D+A")

    } else {
        syntax_error(line.segment)
    }

    if line.command == "push" {
        if line.segment == "constant" {
            append(&translated_lines^, "D=A")
        } else {
            append(&translated_lines^, "D=M")
        }
        append(&translated_lines^, "@SP")
        append(&translated_lines^, "A=M")
        append(&translated_lines^, "M=D")
        append(&translated_lines^, "@SP")
        append(&translated_lines^, "M=M+1")

    } else {
        append(&translated_lines^, "D=A")
        append(&translated_lines^, "@R13")
        append(&translated_lines^, "M=D")
        append(&translated_lines^, "@SP")
        append(&translated_lines^, "AM=M-1")
        append(&translated_lines^, "D=M")
        append(&translated_lines^, "@R13")
        append(&translated_lines^, "A=M")
        append(&translated_lines^, "M=D")
    }
}

process_line :: proc(line: Line, translated_lines: ^[dynamic]string) {

    arithmetic_commands := [?]string {"add", "sub", "eq", "lt", "and", "or", "not"}
    stack_commands := [?]string {"push", "pop"}

    assert(line.command != "")
    is_arithmetic_command := false
    for s in arithmetic_commands {
        if line.command == s {
            is_arithmetic_command = true
        }
    }
    is_stack_command := false
    for s in stack_commands {
        if line.command == s {
            is_stack_command = true
        }
    }
    if is_arithmetic_command {
        process_arithmetic(line, translated_lines)
    } 
    if is_stack_command {
        process_push_pop(line, translated_lines)    
    }
    if line.segment == "" {
        return
    }
    if line.index == "" {
        return
    }
}

write_to_file :: proc(translated_lines: ^[dynamic]string) {
    data_string := strings.join(translated_lines[:], "\n", context.allocator)
    bytes := transmute([]u8)data_string
    os.write_entire_file("./out.asm", bytes)
}

main :: proc() {
    lines := lines_init()
    parse_lines := [dynamic]Line {}
    translated_lines := [dynamic]string {}
    read_file_by_lines_in_whole("./vmcode.txt", &lines)
    parse_files(&lines, &parse_lines)
    for line in parse_lines {
        process_line(line, &translated_lines)
    }    
    write_to_file(&translated_lines)
    lines_destroy(&lines)
    delete(parse_lines)
    delete(translated_lines)
}
