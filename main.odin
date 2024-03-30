package main

import "core:fmt"
import "core:os"
import "core:strings"

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

process_push_pop :: proc(line: Line) {

    m := map[string]string {
        "local" = "@LCL",
        "argument" = "@ARG",
        "this" = "@THIS",
        "that" = "@THAT",
        "static" = "16",
        "temp" = "5",
        "point" = "3",
    }
    
    if line.segment == "constant" {
        assert(line.command != "pop")
    }
    fmt.println(line)
}

process_line :: proc(line: Line) {

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
        // TODO: support math
    } 
    if is_stack_command {
        process_push_pop(line)    
    }
    if line.segment == "" {
        return
    }
    if line.index == "" {
        return
    }
}

main :: proc() {
    lines := lines_init()
    parse_lines := [dynamic]Line {}
    read_file_by_lines_in_whole("./vmcode.txt", &lines)
    parse_files(&lines, &parse_lines)
    for line in parse_lines {
        process_line(line)
    }    
    lines_destroy(&lines)
    delete(parse_lines)
}
