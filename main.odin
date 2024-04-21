package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"

FILE_NAME ::"./vmcode.vm" 
FILE_NAME_OUT ::"./vmcode.asm" 

Line :: struct {
    command: string,
    segment: string,
    index: string,
    line_number: string,
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
            if line[0] == '/' {
                continue
            }
            append(&lines.lines, line)
        }
    }
}

parse_files :: proc(lines: ^Lines_State, parse_lines: ^[dynamic]Line) {
    for line, i in lines.lines {

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

        buf := make([]byte, 4, context.allocator)

        line_number_str := strconv.itoa(buf,i + 1)// + 1 because the line number has to start at 1 
        new_parsed_line := Line{command, segment, index, line_number_str}

        append(parse_lines, new_parsed_line)
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
        append(translated_lines, "@SP")
        append(translated_lines, "A=M-1")
        m_eq_m_blank_d := strings.concatenate({"M=M", m[line.command], "D"}) 
        append(translated_lines, m_eq_m_blank_d)
        return
    }
    
    append(translated_lines, "@SP")
    append(translated_lines, "AM=M-1")
    append(translated_lines, "D=M")
    append(translated_lines, "A=A-1")

    if line.command == "add" ||
        line.command == "sub" ||
        line.command == "and" ||
        line.command == "or" {
        
        value_to_append := strings.concatenate({"M=M", m[line.command], "D"})
        append(translated_lines, value_to_append)
    } else if line.command == "eq" ||
                line.command == "gt" ||
                line.command == "lt" {
        // TODO: eq gr lt
        // append(translated_lines, "D=M-D")
        // append(translated_lines, "D=M-D")
    } else {
        syntax_error(line.command)
    }
}

syntax_error :: proc(at: string) {
    fmt.println("Syntax error @", at)
    os.exit(-1)
}

append_at_sym :: proc(index: string) -> string {
    return strings.concatenate({"@", index, "\n"})
}

append_ataddr :: proc(line_number: string) -> string {
    return strings.concatenate({"@addr_", line_number, "\n"})
}

process_pop :: proc(line: Line, translated_lines: ^[dynamic]string, m: map[string]string) {
    if line.segment == "local" ||
        line.segment == "argument" ||
        line.segment == "this" ||
        line.segment == "that" ||
        line.segment == "pointer" {
        
        line_to_append := strings.concatenate({
            m[line.segment],"\n",
            "D=M\n",
            append_at_sym(line.index),
            "D=D+A\n",
            append_ataddr(line.line_number),
            "M=D\n@SP\nM=M-1\nA=M\nD=M\n",
            append_ataddr(line.line_number),
            "A=M\nM=D\n",
        })
        append(translated_lines, line_to_append)}
    if line.segment == "temp" {
        line_to_append := strings.concatenate({
            m[line.segment],"\n",
            "D=A\n", // this is D=A which is the difference between temp and the others
            append_at_sym(line.index),
            "D=D+A\n",
            append_ataddr(line.line_number),
            "M=D\n@SP\nM=M-1\nA=M\nD=M\n",
            append_ataddr(line.line_number),
            "A=M\nM=D\n",
        })
        append(translated_lines, line_to_append)
    } else if line.segment == "static" {
        line_to_append := strings.concatenate({
            "@SP\nM=M-1\nA=M\nD=M\n",
            "@", FILE_NAME, ".", line.index, "\n",
            "M=D\n",
        })
        append(translated_lines, line_to_append)
    }
}

process_push :: proc(line: Line, translated_lines: ^[dynamic]string, m: map[string]string) {

    if line.segment == "constant" {

        line_to_append := strings.concatenate({
            append_at_sym(line.index),
            "D=A\n@SP\nA=M\nM=D\n@SP\nM=M+1\n",
        })
        append(translated_lines, line_to_append)

    } else if line.segment == "local" ||
              line.segment == "argument" ||
              line.segment == "this" ||
              line.segment == "that" {

        line_to_append := strings.concatenate({
            m[line.segment], "\n",
            "D=M\n",
            append_at_sym(line.index),
            "D=D+A\nA=D\nD=M\n@SP\nA=M\nM=D\n@SP\nM=M+1\n",
        })
        append(translated_lines, line_to_append)

    } else if line.segment == "pointer" ||
              line.segment == "temp" {
        
        line_to_append := strings.concatenate({
            m[line.segment],"\n",
            "D=A\n",
            append_at_sym(line.index),
            "D=D+A\nA=D\nD=M\n@SP\nA=M\nM=D\n@SP\nM=M+1\n",
        })
        append(translated_lines, line_to_append)

    } else if line.segment == "static" {
                
        line_to_append := strings.concatenate({
            "@", FILE_NAME, ".", line.index, "\n",
            append_at_sym(line.index),
            "D=M\n@SP\nA=M\nM=D\n@SP\nM=M+1\n",
        })
        append(translated_lines, line_to_append)
    }
}

process_line :: proc(line: Line, translated_lines: ^[dynamic]string) {

    arithmetic_commands := [?]string {"add", "sub", "eq", "lt", "and", "or", "not"}
    stack_commands := [?]string {"push", "pop"}

    m := map[string]string {
        "local" = "@LCL",
        "argument" = "@ARG",
        "this" = "@THIS",
        "that" = "@THAT",
        "static" = "@16",
        "temp" = "@5",
        "pointer" = "@3",
    }

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
        if line.command == "push" {
            process_push(line, translated_lines, m)    
        } else if line.command == "pop"{
            process_pop(line, translated_lines, m)
        }     
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
    os.write_entire_file(FILE_NAME_OUT, bytes)
}

main :: proc() {
    lines := lines_init()
    parse_lines := [dynamic]Line {}
    translated_lines := [dynamic]string {}
    read_file_by_lines_in_whole(FILE_NAME, &lines)
    parse_files(&lines, &parse_lines)
    for line in parse_lines {
        process_line(line, &translated_lines)
    }    
    write_to_file(&translated_lines)
    lines_destroy(&lines)
    delete(parse_lines)
    delete(translated_lines)
}
