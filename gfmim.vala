using Gtk;

// Commands {{{

// Common declarations {{{2
errordomain GfmimCommandError
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
    public int count;
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

                stderr.printf("parsing: <%s>\n", match[3]);

                if (match[1] != "" || match[2] != "") {
                    range = GfmimCommandRange();
                    range.firstline = match[1];
                    range.lastline  = match[2];
                } else if (match[3] != "") {
                    count = match[3].to_int();
                }
                if (match[0].len() < command.len())
                    argline = command.substring(match[0].len());
                return;
            }
        } catch (RegexError e) {
            stderr.printf("command regex error: %s\n", e.message);
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
        for (int i = 0; i < args.len(); i++)
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
                    arg.str = "";
                }
                else
                {
                    str = true;
                }
            }
            else if (c == ' ')
            {
                result += arg.str;
                arg.str = "";
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
            if (this.argline.len() > 0)
                throw new GfmimCommandError.TrailingChars("E488: trailing characters");
            break;
        case GfmimCommandNargs.SINGLE:
        case GfmimCommandNargs.MANY:
            if (this.argline.len() < 1)
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
            if (this.argline.len() > 0)
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

    public string shortname { get { return _shortname; } }
    public string fullname { get { return _fullname; } }

    public string name {
        get { return _name; }
        protected set {
            _name = value;
            string? part = _name.str("[");
            if (part == null) {
                _fullname = _shortname = _name;
            } else {
                _shortname = _name.substring(0, _name.len()-part.len());
                _fullname  = _shortname + part.substring(1, part.len()-2);
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
        return name.len() >= this._shortname.len() && this._fullname.has_prefix(name);
    }

    public virtual void execute(Gtk.Widget source, GfmimCommandParser parser) throws GfmimCommandError
    {
        parser.parse_args(this._num_args);
        if (this.check(parser))
            this.activate(source, parser);
        return;
    }

    public signal void activate(Gtk.Widget source, GfmimCommandParser parser);
}
// 2}}}

// Implemented commands {{{2

public class GfmimCommandEchoerr: GfmimCommand
{
    public GfmimCommandEchoerr()
    {
        this.name    = "echoe[rr]";
        this._num_args  = GfmimCommandNargs.SINGLE;
        this.activate.connect((s, p) => { (s as GfmimWindow).statusbar.show_error(p.args[0]); });
    }
}

public class GfmimCommandEcho : GfmimCommand
{
    public GfmimCommandEcho()
    {
        this._num_args = GfmimCommandNargs.SINGLE;
        this.name = "ec[ho]";
        this.activate.connect((s, p) => { (s as GfmimWindow).statusbar.show_message(p.args[0]); });
    }
}

public class GfmimCommandQuit : GfmimCommand
{
    public GfmimCommandQuit()
    {
        this._has_bang = true;
        this.name = "q[uit]";
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

    public void execute(Gtk.Widget source, string command) throws GfmimCommandError
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
    public GfmimMapping(string keyname)
    {
        _keyname = keyname;
    }

    private string _keyname = "";
    private uint _keycode   = 0;
    private string _keystr  = "";

    public bool match_key(Gdk.EventKey key)
    {
        stderr.printf("that key: %u, %s, %s\n", key.keyval, key.str, Gdk.keyval_name(key.keyval));
        stderr.printf("this key: %u, %s, %s\n", this._keycode, this._keystr, this._keyname);
        /*return this._keycode == key.keyval || this._keystr == key.str || Gdk.keyval_name(key.keyval) == this._keyname;*/
        return this._keycode == key.keyval || Gdk.keyval_name(key.keyval) == this._keyname;
    }

    public signal void activate(Gtk.Window source, int count = 0);
}

public class GfmimMappings
{
    private GLib.List<GfmimMapping> list;

    public GfmimMappings()
    {
        GfmimMapping map;
        list = new GLib.List<GfmimMapping>();

        map = new GfmimMapping("colon");
        map.activate.connect((s, c) => { (s as GfmimWindow).change_mode(GfmimMode.COMMAND); });
        list.append(map);

        map = new GfmimMapping("Q");
        map.activate.connect((s, c) => { (s as GfmimWindow).execute_command("quit"); });
        list.append(map);
    }

    /*public static GfmimMapping make_mapping(string keyname, GfmimMapping.perform perform)*/
    /*{*/
        /*var result = new GfmimMapping(keyname);*/
        /*result.activate.connect(perform);*/
        /*return result;*/
    /*}*/

    public GfmimMapping? find_mapping(Gdk.EventKey key)
    {
        foreach (GfmimMapping map in this.list)
        {
            if (map.match_key(key))
            {
                return map;
            }
        }
        return null;
    }

    public void execute(Gtk.Window source, Gdk.EventKey key)
    {
        GfmimMapping map = this.find_mapping(key);
        if (map != null) map.activate(source, 0);
    }
}

// }}}

public enum GfmimMode
{
    NORMAL,
    COMMAND,
    VISUAL,
    SEARCH,
}

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
        var list = yield dir.enumerate_children_async(
            FILE_ATTRIBUTE_STANDARD_NAME +","
            + FILE_ATTRIBUTE_STANDARD_TYPE,
            0, Priority.DEFAULT, null);

        while (true)
        {
            var files = yield list.next_files_async(10, Priority.DEFAULT, null);
            if (files == null) break;
            foreach (var finfo in files)
            {
                TreeIter item;
                this.tree_store.append(out item, this.root_dir);
                this.tree_store.set(item, 0, finfo.get_name());
                /*stderr.printf("name: %s, type: %d, dirtype: %d\n", finfo.get_name(), finfo.get_file_type(), GLib.FileType.DIRECTORY);*/
                if (finfo.get_file_type() == GLib.FileType.DIRECTORY)
                {
                    /*stderr.printf("dir: %s\n", finfo.get_name());*/
                    var subloader = new GfmimFilesLoader.from_iter(item, this.root_dir_name + "/" + finfo.get_name(), this.tree_store);
                    this.subloaders.append(subloader);
                    subloader.load_dir();
                }
            }
        }
    }
}

public class GfmimFilesStore : Gtk.TreeStore
{
    private GfmimFilesLoader loader;

    public GfmimFilesStore()
    {
        GLib.Type[] types = { typeof(string) };
        set_column_types(types);
    }

    public void load_dir(string dirname)
    {
        this.loader = new GfmimFilesLoader(dirname, this);
        this.loader.load_dir();
    }
}
// }}}

public class GfmimTreeView : Gtk.TreeView
{
    public ScrolledWindow scroller { get; private set; }

    public GfmimTreeView(GfmimFilesStore model)
    {
        set_model(model);
        insert_column_with_attributes(-1, "Filename", new CellRendererText(), "text", 0);

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
            this.change_mode(GfmimMode.NORMAL);
            this.execute_command(cmd);
            return true;
        }
        return false;
    }

    public void change_mode(GfmimMode newmode)
    {
        this.mode = newmode;
        switch (newmode)
        {
            case GfmimMode.NORMAL:
                this.statusbar.close_command_line();
                this.key_press_event.disconnect(command_key_press_handler);
                this.key_press_event.connect(normal_key_press_handler);
            break;
            case GfmimMode.COMMAND:
                this.key_press_event.disconnect(normal_key_press_handler);
                this.key_press_event.connect(command_key_press_handler);
                this.statusbar.open_command_line(":");
            break;
            default:
            break;
        }
    }

    private GfmimMode mode = GfmimMode.NORMAL;
    public GfmimStatusbar statusbar;
    private GfmimCommands commands;
    private GfmimMappings mappings;

    private GfmimFilesStore fs_store;
    private GfmimTreeView fs_tree;

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
        statusbar.command_line.focus_out_event.connect((src, ev) => { this.change_mode(GfmimMode.NORMAL); return false; });

        fs_store = new GfmimFilesStore();
        fs_tree = new GfmimTreeView(fs_store);

        var vbox = new VBox(false, 0);
        /*vbox.pack_start();*/
        vbox.pack_start(fs_tree.scroller, true, true, 0);
        vbox.pack_start(statusbar, false, false, 0);
        add(vbox);

        commands = new GfmimCommands();
        mappings = new GfmimMappings();
        change_mode(GfmimMode.NORMAL);

        fs_store.load_dir("/home/kstep/doc");
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

