#!/usr/bin/env ruby
# ruby-cairo - Ruby bindings for Cairo.
# Copyright (C) 2003 Evan Martin <martine@danga.com>
# 
# vim: tabstop=2 shiftwidth=2 expandtab :

require 'load_api'

$FILE_HEADER = '/* ruby-cairo - Ruby bindings for Cairo.
 * Copyright (C) 2003 Evan Martin <martine@danga.com>
 *
 * vim: tabstop=4 shiftwidth=4 noexpandtab :
 */

/* this file was autogenerated by gen.rb, available in the ruby-cairo cvs. */

#include "rbcairo.h"

'

$funcs, $structs, enums = load_api(ARGV[0])
$enums = {}
enums.each { |type, defs|
  $enums[type] = defs
}

structs_to_r = {
  'cairo_t *'         => "Cairo",
  'cairo_surface_t *' => "Surface",
  'cairo_matrix_t *'  => "Matrix",
}

special = {}
[
  # functions handled by ruby objects
  'cairo_create',
  'cairo_reference',
  'cairo_destroy',
  'cairo_copy',

  'cairo_set_target_image',  # need special Cairo::Image class
  'cairo_set_target_ps',     # need special file handling

  'cairo_set_dash',          # takes an array of dashes via double* ?

  # take points and modify them directly
  'cairo_transform_point',
  'cairo_transform_distance',
  'cairo_inverse_transform_point',
  'cairo_inverse_transform_distance',

  'cairo_stroke',            # special-cased so you can pass blocks.
  'cairo_fill',

  'cairo_current_rgb_color', # returns a color triple

  # surfaces
  'cairo_surface_create_for_image',
  'cairo_surface_create_similar',
  'cairo_surface_create_similar_solid',
  'cairo_surface_reference',
  'cairo_surface_destroy',
  'cairo_surface_get_matrix',

  # matrices
  'cairo_matrix_create',
  'cairo_matrix_destroy',
  'cairo_matrix_copy',
].each { |func| special[func] = 1 }

def r_from_c(type)
  map = {
    'const char *' => 'rb_str_new2',
    'double' => 'rb_float_new',
    'cairo_surface_t *' => 'rsurface_new_from',
  }
  return map[type] if map.has_key? type
  return 'INT2FIX' if $enums.has_key? type
  return nil
end

def c_from_r(arg)
  c_from_r = {
    'cairo_matrix_t *' => 'rmatrix_get_matrix',
    'cairo_surface_t *' => 'rsurface_get_surface',
    'double' => 'NUM2DBL',
    'const char *' => 'STR2CSTR',
    'const unsigned char *' => 'STR2CSTR',
    'int' => 'FIX2INT'
  }
  return c_from_r[arg] if c_from_r.has_key? arg
  return 'NUM2INT' if $enums.has_key? arg
  return nil
end

class GMethod
  attr_accessor :cname, :name, :ret, :args
  def initialize(cname, name, ret, args)
    @cname = cname; @name = name; @ret = ret; @args = args
  end
  def header
    "static VALUE\nr#{@cname}(VALUE self" + \
      @args.map { |type, name| ", VALUE #{name}" }.join("") + ") {"
  end
  def args_to_c
    if @args
      @args.map { |type, name|
        ", #{c_from_r(type)}(#{name})"
      }.join("")
    else
      ""
    end
  end
end

def mappable_args(args)
  args.each { |type, name|
    unless c_from_r(type)
      dputs "don't know how to automatically handle #{type}"
      return false 
    end
  }
  return true
end

class GClass
  attr_accessor :name, :setters, :getters, :methods
  def initialize(name, cname, ctype)
    @name = name
    @rname = name.gsub(/^Cairo(.+)/) { $1 }
    @cname = cname
    @ctype = ctype
    @setters = []
    @getters = []
    @methods = []
  end

  def unwrap_str
    "r#{@cname}_get_#{@cname}(self)"
  end

  def out_setters(out)
    @setters.each { |m|
      out << m.header + "\n"
      out << "\t#{m.cname}(#{unwrap_str}" + m.args_to_c + ");\n"
      out << "\treturn Qnil;\n"
      out << "}\n"
    }
  end
  def out_getters(out)
    @getters.each { |m|
      out << m.header + "\n"
      ret = r_from_c(m.ret) || 'XXX'
      out << "\treturn #{ret}(#{m.cname}(#{unwrap_str}));\n"
      out << "}\n"
    }
  end
  def out_methods(out)
    @methods.each { |m|
      out << m.header + "\n"
      out << "\t#{m.cname}(#{unwrap_str}" + m.args_to_c + ");\n"
      out << "\treturn Qnil;\n"
      out << "}\n"
    }
  end

  def out_defs(out)
    out << "\tc#{@name} = rb_define_class_under(mCairo, \"#{@rname}\", rb_cObject);\n"

    @methods.each { |m|
      out << "\trb_define_method(c#{@name}, \"#{m.name}\", r#{m.cname}, #{m.args.length});\n"
    }

    @setters.each { |m|
      out << "\trb_define_method(c#{@name}, \"set_#{m.name}\", r#{m.cname}, #{m.args.length});\n"
      if m.args.length == 1
        out << "\trb_define_method(c#{@name}, \"#{m.name}=\", r#{m.cname}, #{m.args.length});\n"
      end
    }
    @getters.each { |m|
      out << "\trb_define_method(c#{@name}, \"#{m.name}\", r#{m.cname}, 0);\n"
    }
  end

  def add_method(m)
    return false unless m.args[0][0] == @ctype and         # methods must operate on this, and
      (m.args.length < 2 or mappable_args(m.args[1..-1]))  # we must know how to handle args

    type, subname = $1, $2 if m.name =~ /(.+?)_(.+)/ 
    m.args.shift
    if m.ret and c_from_r(m.ret) and m.args.length == 0
      m.name = subname if type == 'get' or type == 'current'
      @getters << m
    elsif type == 'set'
      m.name = subname
      @setters << m
    elsif not m.ret
      @methods << m
    else
      return false
    end
    return true
  end

  def write(out)
    out_setters(out)
    out << "\n"
    out_getters(out)
    out << "\n"
    out_methods(out)
    out << "\n"
    out << "VALUE gen_#{@name}(void) {\n"
    out_defs(out)
    out << "\treturn c#{@name};\n"
    out << "}\n"
  end
end

$classes = {
  'Cairo' => GClass.new("Cairo", 'cairo', 'cairo_t *'),
  'Surface' => GClass.new("CairoSurface", 'surface', 'cairo_surface_t *'),
  'Matrix' => GClass.new("CairoMatrix", 'matrix', 'cairo_matrix_t *'),
}

def dputs(*args)
  $stdout.puts(*args)
end

$funcs.each { |func, ret, args|
  if special.has_key? func
    dputs "* #{func} is marked for special handling"
    next
  end

  added = case func
  when /cairo_matrix_(\w+)/
    $classes['Matrix'].add_method(GMethod.new(func, $1, ret, args))
  when /cairo_surface_(\w+)/
    $classes['Surface'].add_method(GMethod.new(func, $1, ret, args))
  when /cairo_(\w+)/
    $classes['Cairo'].add_method(GMethod.new(func, $1, ret, args))
  else
    false
  end

  if added
    dputs "* #{func}"
  else
    dputs " -> don't know what to do with #{func}"
  end
}

$classes.each_value { |c|
  File.open("../src/gen-#{c.name}.c", "w") { |f|
  puts "Generating #{c.name}..."
    f << $FILE_HEADER
    c.write(f)
  }
}

File.open("../src/gen-constants.c", "w") { |f|
  puts "Generating constants..."
  f << $FILE_HEADER
  $enums.each { |type, defs|
    type = type[0..-3]
    rtype = type.split(/_/).map{|x| x.capitalize}.join('')
    f << "static void\ninit_#{type}(void) {\n"
    shortrtype = rtype.sub(/^Cairo/, '')
    f << "\tVALUE m#{rtype} = rb_define_module_under(mCairo, \"#{shortrtype}\");\n"
    defs.each { |d|
      shortdef = d[(type.length+1)..-1]
      f << "\trb_define_const(m#{rtype}, \"#{shortdef}\", INT2NUM(#{d}));\n"
    }
    f << "}\n\n"
  }

  f << "\n"
  f << "void\nconstants_init(void) {\n"
  $enums.each { |type, defs|
    type = type[0..-3]
    f << "\tinit_#{type}();\n"
  }
  f << "}\n"
}
