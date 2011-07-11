using Gtk;
// modules: gtk+-2.0 gmodule-2.0 posix

// Commands {{{

// Common declarations {{{2
public errordomain GfmimCommandError
{
    NotFound,
    NotParseable,
    Incorrect,
    TrailingChars,
    ArgRequired,
    NoBangAllowed,
    NoRangeAllowed,
}

public struct GfmimCommandRange
{
    string firstline;
    string lastline;
}

public enum GfmimCommandNargs
{
    NONE,   // 0
    SINGLE, // 1
    ANY,    // *
    ONE,    // ?
    MANY,   // +
}

public class GfmimCommandParser
{
    public string name;
    public bool bang;
    public uint count;
    public GfmimCommandRange? range;
    public string argline;
    public string[] args;

    public GfmimCommandParser(string command) throws GfmimCommandError
    {
        try {
            // 1,2 => range, 3 => count, 4 => name, 5 => bang, the rest is args
            var re = new Regex("^(?:(\\.|(?:\\.[+-])?[0-9]+|'[a-z<>])(?:,((?:\\.[+-])?[0-9]+|'[a-z<>]))?|([0-9]+))?([A-Za-z][A-Za-z0-9_]*)(\\!)?\\s*");
            MatchInfo matches;
            if (re.match(command, 0, out matches))
            {
                string[] match = matches.fetch_all();

                name = match[4];
                bang = match[5] == "!";
                argline = "";

                stderr.printf("parsing: <%s>\n", match[4]);

                if (match[1] != "" || match[2] != "") {
                    range = GfmimCommandRange();
                    range.firstline = match[1];
                    range.lastline  = match[2];
                } else if (match[3] != "") {
                    count = int.parse(match[3]);
                }
                if (match[0].length < command.length)
                    argline = command.substring(match[0].length);
                return;
            }
        } catch (RegexError e) {
        }
        throw new GfmimCommandError.NotParseable("Error parsing command: %s\n".printf(command));
    }

    private string[] split_string(string args)
    {
        // строка разбивается через пробелы,
        // пробелы с символом \ перед ними игнорируются и заменяются на простые пробелы,
        // строки в кавычках " воспринимаются как один аргумент, кавычки с символом \ перед ними игнорируются.
        // последовательности \x заменяются на простые символы x.
        bool esc = false;
        bool str = false;
        string[] result = {};
        var arg = new StringBuilder();
        for (int i = 0; i < args.length; i++)
        {
            unichar c = args[i];
            if (esc) { arg.append_unichar(c); esc = false; }
            else if (c == '\\') esc = true;
            else if (c == '"')
            {
                if (str)
                {
                    str = false;
                    result += arg.str;
                    arg.truncate(0);
                }
                else
                {
                    str = true;
                }
            }
            else if (c == ' ')
            {
                result += arg.str;
                arg.truncate(0);
            }
            else arg.append_unichar(c);
        }
        return result;
    }

    public void parse_args(GfmimCommandNargs num_args) throws GfmimCommandError.TrailingChars, GfmimCommandError.ArgRequired
    {
        this.args = {};
        switch (num_args)
        {
        case GfmimCommandNargs.NONE: 
            if (this.argline.length > 0)
                throw new GfmimCommandError.TrailingChars("E488: trailing characters");
            break;
        case GfmimCommandNargs.SINGLE:
        case GfmimCommandNargs.MANY:
            if (this.argline.length < 1)
                throw new GfmimCommandError.ArgRequired("E475: argument required");
            if (num_args == GfmimCommandNargs.MANY)
                this.args = this.split_string(this.argline);
            else
                this.args = { this.argline };
            break;
        case GfmimCommandNargs.ANY:
            this.args = this.split_string(this.argline);
            break;
        case GfmimCommandNargs.ONE:
            if (this.argline.length > 0)
                this.args = { this.argline };
            break;
        default:
            break;
        }
    }
}

public class GfmimCommand
{
    protected string _name      = "";
    protected string _shortname = "";
    protected string _fullname  = "";

    protected bool _has_bang  = false;
    protected bool _has_range = false;
    protected GfmimCommandNargs _num_args = GfmimCommandNargs.NONE;
    protected int _def_count = -1;
    protected bool _system = false;

    public string shortname { get { return _shortname; } }
    public string fullname { get { return _fullname; } }

	public GfmimCommand.full(string name, GfmimCommandNargs nargs=GfmimCommandNargs.NONE,
						bool has_bang=false, bool has_range=false, bool system=false) {
		this.name = name;
		this._has_bang = has_bang;
		this._has_range = has_range;
		this._num_args = nargs;
		this._system = system;
	}

    public string name {
        get { return _name; }
        protected set {
            _name = value;
            int part = _name.index_of("[");
            if (part == -1) {
                _fullname = _shortname = _name;
            } else {
                _shortname = _name[0:part];
                _fullname  = _shortname + _name[part+1:-1];
            }
        }
    }

    public bool check(GfmimCommandParser parser) throws GfmimCommandError.NoBangAllowed, GfmimCommandError.NoRangeAllowed
    {
        if (parser.bang && !this._has_bang) throw new GfmimCommandError.NoBangAllowed("E477: ! is not allowed");
        if (parser.range != null && !this._has_range) throw new GfmimCommandError.NoRangeAllowed("E481: no range allowed");
        return true;
    }

    public bool match_name(string name)
    {
        return name.length >= this._shortname.length && this._fullname.has_prefix(name);
    }

    public virtual void execute(GfmimWindow source, GfmimCommandParser parser) throws GfmimCommandError
    {
        parser.parse_args(this._num_args);
        if (this.check(parser))
            this.activate(source, parser);
        return;
    }

    public signal void activate(GfmimWindow source, GfmimCommandParser parser);
}
// 2}}}

// Implemented commands {{{2

public class GfmimCommandEchoerr: GfmimCommand
{
    public GfmimCommandEchoerr()
    {
        this.name    = "echoe[rr]";
        this._system = true;
        this._num_args  = GfmimCommandNargs.SINGLE;
        this.activate.connect((s, p) => { s.statusbar.show_error(p.args[0]); });
    }
}

public class GfmimCommandEcho : GfmimCommand
{
    public GfmimCommandEcho()
    {
        this.name = "ec[ho]";
        this._system = true;
        this._num_args = GfmimCommandNargs.SINGLE;
        this.activate.connect((s, p) => { s.statusbar.show_message(p.args[0]); });
    }
}

public class GfmimCommandQuit : GfmimCommand
{
    public GfmimCommandQuit()
    {
        this.name = "q[uit]";
        this._system = true;
        this._has_bang = true;
        this.activate.connect((s, p) => { s.destroy(); });
    }
}

// 2}}}

// Commands collection {{{2

public class GfmimCommands
{
    private GLib.List<GfmimCommand> list;

    public GfmimCommands()
    {
        list = new GLib.List<GfmimCommand>();
        list.append(new GfmimCommandQuit());
        list.append(new GfmimCommandEcho());
        list.append(new GfmimCommandEchoerr());
    }

    public GfmimCommand find_command(string name) throws GfmimCommandError.NotFound
    {
        foreach (GfmimCommand cmd in this.list)
        {
            stderr.printf("test cmd: %s\n", cmd.fullname);
            if (cmd.match_name(name))
            {
                return cmd;
            }
        }
        throw new GfmimCommandError.NotFound("E492: command not found: %s".printf(name));
    }

    public void execute(GfmimWindow source, string command) throws GfmimCommandError
    requires (command != "")
    {
        var parser = new GfmimCommandParser(command);
        GfmimCommand cmd = this.find_command(parser.name);
        cmd.execute(source, parser);
    }
}

// 2}}}

// }}}

// Command & status lines {{{

public class GfmimCommandLine : Gtk.Entry
{
    public GfmimCommandLine()
    {
        has_frame = false;
        hide();
    }
}

public class GfmimStatusbar : Gtk.HBox
{
    public Gtk.Label message;
    public GfmimCommandLine command_line;

    public GfmimStatusbar()
    {
        /*has_resize_grip = false;*/
        message = new Gtk.Label("");
        message.use_markup = true;
        command_line = new GfmimCommandLine();
        command_line.focus_out_event.connect((src, ev) => { this.message.label = ""; return false; });
        pack_start(message, false, false, 0);
        pack_start(command_line, true, true, 0);
    }

    public void show_message(string text)
    {
        this.command_line.hide();
        this.message.label = text;
    }

    public void show_error(string text)
    {
        this.show_message("<span color=\"white\" bgcolor=\"red\"><b>%s</b></span>".printf(text));
    }

    public void open_command_line(string pfx)
    {
        this.message.label = pfx;
        this.command_line.text = "";
        this.command_line.show();
        this.command_line.grab_focus();
    }

    public void close_command_line()
    {
        this.command_line.hide();
        this.command_line.text = "";
    }

    public string get_command_line()
    {
        return this.command_line.text;
    }
}
// }}}

// Mappings {{{

public class GfmimMapping
{
    public enum KeyMod { ANY = ~0, SHIFT = 1, CONTROL = 4, META = 8, SUPER = 67108928, ALL = 1|4|8|67108928 }

    private bool _system = false;
    private string _keyname = "";
    private uint[] _keyseq = {};
    private uint[] _keymod = {};

    public GfmimMapping(string key, bool system = false)
    {
        keyname = key;
        _system = system;
    }

    public string keyname {
        get { return _keyname; }
        protected set {
            _keyname = value;
            _keyseq = {};
            _keymod = {};

            int inkey = 0;
            var composed_key = new StringBuilder();
            for (int i = 0; i < _keyname.length; i++)
            {
                unichar c = _keyname[i];
                if (c == '<') {
                    inkey++;
                    if (inkey == 1)
                        continue;
                } else if (c == '>' && inkey > 0) {
                    inkey--;
                    if (inkey == 0 && composed_key.str != "")
                    {
                        uint mods = 0;
                        string ckey = composed_key.str;
                        composed_key.truncate(0);

                        while (ckey.length > 2 && ckey[1] == '-')
                        {
                            switch (ckey[0])
                            {
                            case 'S':
                            case 's':
                                mods |= KeyMod.SHIFT;
                            break;
                            case 'C':
                            case 'c':
                                mods |= KeyMod.CONTROL;
                            break;
                            case 'M':
                            case 'm':
                                mods |= KeyMod.META;
                            break;
                            case 'T':
                            case 't':
                                mods |= KeyMod.SUPER;
                            break;
                            default:
                            break;
                            }
                            ckey = ckey.substring(2, 1);
                        }

                        _keymod += mods == 0 ? KeyMod.ANY : mods;
                        _keyseq += Gdk.keyval_from_name(ckey);
                        continue;
                    }
                }

                if (inkey > 0)
                {
                    composed_key.append_unichar(c);
                }
                else
                {
                    _keyseq += Gdk.unicode_to_keyval(c);
                    _keymod += KeyMod.ANY;
                }
            }
        }
    }

    /**
    1. разбить на keyname на последовательность символов:
    1.1. просто символ означает конкретную нажатую клавишу, сравнивается с key.str,
    1.2. части строки, заключённые в <> воспринимаются как один символ, сравниваются с Gdk.keyval_name(key.keyval),
    при это учитывается состояние модификаторов, если они есть.
    маски модификаторов:
    <C-> => 4,
    <M-> => 8,
    <S-> => 1,
    <T-> => 67108928.
    */
    public bool match_key(uint[] key, uint[] mod)
    requires (key.length > 0)
    requires (mod.length == key.length)
    {
        stderr.printf("that key: %u\n", key[0]);
        stderr.printf("this key: %u\n", this._keyseq[0]);
        /*return this._keycode == key.keyval || this._keystr == key.str || Gdk.keyval_name(key.keyval) == this._keyname;*/
        if (key.length != this._keyseq.length) return false;
        for (int i = 0; i < key.length; i++)
        {
            stderr.printf("this: %u %u, that: %u %u\n", this._keymod[i], this._keyseq[i], mod[i], key[i]);
            if (key[i] != this._keyseq[i]) return false;
            if (this._keymod[i] != KeyMod.ANY)
                if (mod[i] != this._keymod[i]) return false;
        }
        return true;
    }

    public signal void activate(GfmimWindow source, uint count = 0);
}

public class GfmimMappings
{
    private GLib.List<GfmimMapping> list;

    public GfmimMappings()
    {
        list = new GLib.List<GfmimMapping>();

        this.add_mapping("<colon>").activate.connect((s, c) => { s.change_mode("Command"); });
        this.add_mapping("ZZ").activate.connect((s, c) => { s.execute_command("quit"); });
        this.add_mapping("/").activate.connect((s, c) => { s.change_mode("Search"); });
        this.add_mapping("gg").activate.connect((s, c) => { s.set_cursor(0); });

        this.add_mapping("k").activate.connect((s, c) => { s.move_cursor(c == 0? -1: -((int)c)); });
        this.add_mapping("j").activate.connect((s, c) => { s.move_cursor(c == 0? 1: (int)c); });

        this.add_mapping("<Return>").activate.connect((s, c) => { s.fs_tree.expand_collapse_cursor_row(true, !s.fs_tree.is_row_expanded(s.get_cursor()), false); });
        /*this.add_mapping("<C-a>").activate.connect((s, c) => { s.execute_command("echo it's okey!"); });*/
    }

    public GfmimMapping add_mapping(string keyname)
    {
        var map = new GfmimMapping(keyname, true);
        this.list.append(map);
        return map;
    }

    uint[] key_buffer;
    uint[] key_modifiers;
    uint32 key_timeout;
    uint key_count;

    private void reset_buffers()
    {
        this.key_buffer = {};
        this.key_modifiers = {};
        this.key_count = 0;
    }

    public GfmimMapping? find_mapping(Gdk.EventKey key)
    {
        // сброс по таймауту
        if ((key.time - this.key_timeout) > 1000)
        {
            this.reset_buffers();
        }
        this.key_timeout = key.time;

        // безусловный сброс по Esc
        if (key.keyval == 65307)
        {
            this.reset_buffers();
        }
        // увеличение параметра count
        else if ((key.state == 0) && (47 < key.keyval) && (key.keyval < 58))
        {
            this.key_count *= 10;
            this.key_count += key.keyval - 48;
        }
        // обычная клавиша
        else
        {
            this.key_modifiers += key.state & GfmimMapping.KeyMod.ALL;
            this.key_buffer += key.keyval;
            foreach (GfmimMapping map in this.list)
            {
                if (map.match_key(this.key_buffer, this.key_modifiers))
                {
                    return map;
                }
            }
        }
        return null;
    }

    public void execute(GfmimWindow source, Gdk.EventKey key)
    {
        GfmimMapping map = this.find_mapping(key);
        if (map != null) {
            stderr.printf("key_count: %u\n", this.key_count);
            map.activate(source, this.key_count);
            this.reset_buffers();
        }
    }
}

// }}}

// Modes {{{

public class GfmimMode {
    public string name;
    public signal void enter(GfmimWindow source);
    public signal void leave(GfmimWindow source);

    public GfmimMode(string name) {
        this.name = name;
    }
}

public errordomain GfmimModesError {
    NotFound,
}

public class GfmimModes {
    private GLib.List<GfmimMode> list;
    public GfmimMode current {
        get; private set;
    }

    public GfmimModes() {
        list = new GLib.List<GfmimMode>();
        this.current = new GfmimMode("Normal");
        list.append(current);

        list.append(new GfmimMode("Command"));
        list.append(new GfmimMode("Search"));

    }

    public void set_mode(GfmimWindow source, GfmimMode mode) {
        this.current.leave(source);
        this.current = mode;
        this.current.enter(source);
    }

    public void set_mode_by_name(GfmimWindow source, string name) throws GfmimModesError {
        GfmimMode? mode = this.get_by_name(name);
        if (mode == null) {
            throw new GfmimModesError.NotFound("Mode `%s' not found".printf(name));
        }

        this.set_mode(source, mode);
    }

    public GfmimMode? get_by_name(string name) {
        foreach (GfmimMode mode in this.list) {
            if (mode.name == name) {
                return mode;
            }
        }
        return null;
    }
}

// }}}

// Files tree storage {{{
public class GfmimFilesLoader
{
    private TreeIter? root_dir;
    private string root_dir_name;
    private GfmimFilesStore tree_store;

    private GLib.List<GfmimFilesLoader> subloaders;

    public GfmimFilesLoader(string dirname, GfmimFilesStore store)
    {
        store.append(out root_dir, null);
        store.set(root_dir, 0, dirname);
        root_dir = null;
        tree_store = store;
        root_dir_name = dirname;
    }

    public GfmimFilesLoader.from_iter(TreeIter root, string dirname, GfmimFilesStore store)
    {
        tree_store = store;
        root_dir = root;
        root_dir_name = dirname;
    }

    public void load_dir()
    {
        this.load_dir_async.begin();
    }

    private async void load_dir_async()
    {
        var dir = File.new_for_path(this.root_dir_name);

        try
        {
            var list = yield dir.enumerate_children_async(
                FILE_ATTRIBUTE_STANDARD_NAME +","+
                FILE_ATTRIBUTE_STANDARD_TYPE +","+
                FILE_ATTRIBUTE_STANDARD_CONTENT_TYPE +","+
                FILE_ATTRIBUTE_STANDARD_ICON +","+
                FILE_ATTRIBUTE_OWNER_USER +","+
                FILE_ATTRIBUTE_OWNER_GROUP +","+
                FILE_ATTRIBUTE_UNIX_MODE +","+
                FILE_ATTRIBUTE_STANDARD_SIZE,
                0, Priority.DEFAULT, null);

            while (true)
            {
                var files = yield list.next_files_async(10, Priority.DEFAULT, null);
                if (files == null) break;
                foreach (var finfo in files)
                {
                    TreeIter item;
                    this.tree_store.append(out item, this.root_dir);
                    this.tree_store.set(item,
                        0, finfo.get_name(),
                        1, finfo.get_size(),
                        2, finfo.get_content_type(),
                        3, finfo.get_icon(),
                        4, finfo.get_attribute_uint32(FILE_ATTRIBUTE_UNIX_MODE),
                        5, finfo.get_attribute_string(FILE_ATTRIBUTE_OWNER_USER),
                        6, finfo.get_attribute_string(FILE_ATTRIBUTE_OWNER_GROUP));

                    if (finfo.get_file_type() == GLib.FileType.DIRECTORY)
                    {
                        /*stderr.printf("dir: %s\n", finfo.get_name());*/
                        var subloader = new GfmimFilesLoader.from_iter(item, this.root_dir_name + "/" + finfo.get_name(), this.tree_store);
                        this.subloaders.append(subloader);
                        subloader.load_dir();
                    }
                }
            }
        } catch (GLib.Error e) {
            stderr.printf("Error loading directory content: %s\n", e.message);
        }
    }
}

public class GfmimFilesStore : Gtk.TreeStore
{
    private GfmimFilesLoader loader;

    public GfmimFilesStore()
    {
        GLib.Type[] types = {
            typeof(string), // name
            typeof(int64),  // size
            typeof(string), // mimetype
            typeof(Icon),   // icon
            typeof(uint32), // mode (perm)
            typeof(string), // owner
            typeof(string)  // group
            };
        set_column_types(types);
    }

    public void load_dir(string dirname)
    {
        this.loader = new GfmimFilesLoader(dirname, this);
        this.loader.load_dir();
    }
}
// }}}

public class CellRendererPermText : CellRendererText {
    private uint32 _filemode;

    public uint32 filemode {
        get {
            return _filemode;
        }
        set {
            _filemode = value;
            text = ((value & Posix.S_IRUSR) == 0? "-": "r") +
                   ((value & Posix.S_IWUSR) == 0? "-": "w") +
                   ((value & Posix.S_IXUSR) == 0? "-": "x") +
                   ((value & Posix.S_IRGRP) == 0? "-": "r") +
                   ((value & Posix.S_IWGRP) == 0? "-": "w") +
                   ((value & Posix.S_IXGRP) == 0? "-": "x") +
                   ((value & Posix.S_IROTH) == 0? "-": "r") +
                   ((value & Posix.S_IWOTH) == 0? "-": "w") +
                   ((value & Posix.S_IXOTH) == 0? "-": "x");
        }
    }
}

public class CellRendererSizeText : CellRendererText {
    private int64 _filesize;
    private const int power = 1024;

    public float humanize_size(int64 size, out string unit)
    {
        string[] units = {"b", "Kib", "Mib", "Gib", "Tib", "Pib", "Eib", "Zib", "Yib"};
        float result = size;

        foreach (string u in units) {
            unit = u;
            if (result <= power) break;
            result /= power;
        }
        return result;
    }

    public int64 filesize {
        get {
            return _filesize;
        }
        set {
            float shortsize;
            string unit;

            _filesize = value;
            shortsize = humanize_size(value, out unit);
            text = "%0.2f%s".printf(shortsize, unit);
        }
    }
}

public class GfmimTreeView : Gtk.TreeView
{
    public ScrolledWindow scroller { get; private set; }

    public GfmimTreeView(GfmimFilesStore model)
    {
        set_model(model);
        insert_column_with_attributes(-1, "", new CellRendererPixbuf(), "gicon", 3);
        insert_column_with_attributes(-1, "Filename", new CellRendererText(), "text", 0);
        insert_column_with_attributes(-1, "Size", new CellRendererSizeText(), "filesize", 1);
        insert_column_with_attributes(-1, "Mimetype", new CellRendererText(), "text", 2);
        insert_column_with_attributes(-1, "Perms", new CellRendererPermText(), "filemode", 4);
        insert_column_with_attributes(-1, "Owner", new CellRendererText(), "text", 5);
        insert_column_with_attributes(-1, "Group", new CellRendererText(), "text", 6);

        get_column(1).sort_column_id = 0;
        get_column(2).sort_column_id = 1;
        get_column(3).sort_column_id = 2;
        get_column(4).sort_column_id = 4;
        get_column(5).sort_column_id = 5;
        get_column(6).sort_column_id = 6;

        headers_clickable = true;


        scroller = new ScrolledWindow(null, null);
        scroller.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
        scroller.add(this);
    }

}

public class GfmimWindow : Gtk.Window
{
    [CCode (instance_pos=-1)]
    public bool normal_key_press_handler(Widget source, Gdk.EventKey key)
    {
        stderr.printf("key: s=%u, mod=%u, val=%u, str=%s, name=%s, hk=%u\n", key.state, key.is_modifier, key.keyval, key.str, Gdk.keyval_name(key.keyval), key.hardware_keycode);
        if (key.is_modifier == 0)
        {
            this.mappings.execute(this, key);
            return true;
        }
        return false;
    }

    [CCode (instance_pos=-1)]
    public bool command_key_press_handler(Widget source, Gdk.EventKey key)
    {
        if (key.keyval == 65293)
        {
            string cmd = this.statusbar.get_command_line();
            this.change_mode("Normal");
            if (cmd != "")
                this.execute_command(cmd);
            return true;
        }
        return false;
    }

    public void change_mode(string name)
    {
        try {
            this.modes.set_mode_by_name(this, name);
        } catch (GfmimModesError e) {
            this.statusbar.show_error(e.message);
        }
    }

    public GfmimStatusbar statusbar;
    private GfmimModes modes;
    private GfmimCommands commands;
    private GfmimMappings mappings;

    private GfmimFilesStore fs_store;
    public GfmimTreeView fs_tree;

    private enum FsColumns
    {
        ICON,
        TITLE,
        NCOLS
    }

    public GfmimWindow()
    {
        this.title = "Gfmim";
        this.destroy.connect(Gtk.main_quit);

        statusbar = new GfmimStatusbar();
        statusbar.command_line.focus_out_event.connect((src, ev) => { this.change_mode("Normal"); return false; });

        fs_store = new GfmimFilesStore();
        fs_tree = new GfmimTreeView(fs_store);

        var vbox = new VBox(false, 0);
        /*vbox.pack_start();*/
        vbox.pack_start(fs_tree.scroller, true, true, 0);
        vbox.pack_start(statusbar, false, false, 0);
        add(vbox);

        commands = new GfmimCommands();
        mappings = new GfmimMappings();
        modes = new GfmimModes();

        modes.get_by_name("Normal").enter.connect((source) => {
            source.statusbar.close_command_line();
            source.key_press_event.disconnect(command_key_press_handler);
            source.key_press_event.connect(normal_key_press_handler);
        });
        modes.get_by_name("Command").enter.connect((source) => {
            source.key_press_event.disconnect(normal_key_press_handler);
            source.key_press_event.connect(command_key_press_handler);
            source.statusbar.open_command_line(":");
        });
        modes.get_by_name("Search").enter.connect((source) => {
            source.key_press_event.disconnect(normal_key_press_handler);
            source.key_press_event.connect(command_key_press_handler);
            source.statusbar.open_command_line("/");
        });

        change_mode("Normal");

        fs_store.load_dir("/home/kstep/video");
    }

    public void execute_command(string command)
    {
        try {
            this.commands.execute(this, command);
        } catch (GfmimCommandError e) {
            this.statusbar.show_error(e.message);
        }
        return;
    }

    public void move_cursor(int count=1)
    {
        int dir = count > 0? 1: -1;
        count = count.abs();
        for (int i = 0; i < count; i++) {
            this.fs_tree.move_cursor(Gtk.MovementStep.DISPLAY_LINES, dir);
        }
    }

    public void set_cursor(int line=0)
    {
        var path = new Gtk.TreePath.first();
        for (int i = 0; i < line; i++) {
            path.next();
        }
        this.fs_tree.set_cursor(path, null, false);
    }

    public TreePath get_cursor()
    {
        GLib.List<TreePath> result;
        TreeModel model;
        result = this.fs_tree.get_selection().get_selected_rows(out model);
        return result.nth_data(0);
    }

    public void scroll_to(int x, int y)
    {
        Gtk.TreePath? path;
        Gtk.TreeViewColumn? col;
        int cellx, celly;
        this.fs_tree.get_path_at_pos(x, y, out path, out col, out cellx, out celly);
        this.fs_tree.set_cursor(path, col, false);
    }

    public static int main(string[] args)
    {
        Gtk.init(ref args);
        var window = new GfmimWindow();
        window.destroy.connect(Gtk.main_quit);
        window.show_all();
        Gtk.main();
        return 0;
    }
}

