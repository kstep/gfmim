using Gtk;

// Commands {{{

// Common declarations {{{2
errordomain GvifmCommandError
{
    NotFound,
    NotParseable,
    Incorrect,
    TrailingChars,
    ArgRequired,
    NoBangAllowed,
    NoRangeAllowed,
}

public struct GvifmRange
{
    string firstline;
    string lastline;
}

public enum GvifmCommandNargs
{
    NONE,   // 0
    SINGLE, // 1
    ANY,    // *
    ONE,    // ?
    MANY,   // +
}

public abstract class GvifmCommand
{
    protected string _name      = "";
    protected string _shortname = "";
    protected string _fullname  = "";

    protected bool _has_bang  = false;
    protected bool _has_range = false;
    protected GvifmCommandNargs _num_args = GvifmCommandNargs.NONE;
    protected int _def_count = -1;
    protected GvifmWindow _parent;

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

    public string[] parse_args(string args) throws GvifmCommandError.TrailingChars, GvifmCommandError.ArgRequired
    {
        string[] result = {};
        switch (this._num_args)
        {
        case GvifmCommandNargs.NONE: 
            if (args.len() > 0)
                throw new GvifmCommandError.TrailingChars("E488: trailing characters");
            break;
        case GvifmCommandNargs.SINGLE:
        case GvifmCommandNargs.MANY:
            if (args.len() < 1)
                throw new GvifmCommandError.ArgRequired("E475: argument required");
            if (this._num_args == GvifmCommandNargs.MANY)
                result = this.split_string(args);
            else
                result = { args };
            break;
        case GvifmCommandNargs.ANY:
            result = this.split_string(args);
            break;
        case GvifmCommandNargs.ONE:
            if (args.len() > 0)
                result = { args };
            break;
        default:
            break;
        }
        return result;
    }

    public bool check(bool bang = false, GvifmRange? range = null) throws GvifmCommandError.NoBangAllowed, GvifmCommandError.NoRangeAllowed
    {
        if (bang && !this._has_bang) throw new GvifmCommandError.NoBangAllowed("E477: ! is not allowed");
        if (range != null && !this._has_range) throw new GvifmCommandError.NoRangeAllowed("E481: no range allowed");
        /*int ln = args.length;*/
        /*if ((ln == 0 && this._num_args == GvifmCommandNargs.NONE)*/
            /*|| (ln == 1 && this._num_args == GvifmCommandNargs.SINGLE)*/
            /*|| (ln >= 0 && this._num_args == GvifmCommandNargs.ANY)*/
            /*|| (ln >= 1 && this._num_args == GvifmCommandNargs.MANY)*/
            /*|| (0 <= ln && ln <= 1 && this._num_args == GvifmCommandNargs.ONE))*/
        /*{} else throw new GvifmCommandError.Incorrect("E474: invalid argument");*/
        return true;
    }

    public bool match_name(string name)
    {
        return name.len() >= this._shortname.len() && this._fullname.has_prefix(name);
    }

    public virtual int perform(bool bang = false, GvifmRange? range = null, string args = "") throws GvifmCommandError
    {
        stderr.printf("oops!\n");
        return 0;
    }
}
// 2}}}

// Implemented commands {{{2

public class GvifmCommandEchoerr: GvifmCommand
{
    public GvifmCommandEchoerr(GvifmWindow window)
    {
        this.name    = "echoe[rr]";
        this._num_args  = GvifmCommandNargs.SINGLE;
        this._parent    = window;
    }

    public override int perform(bool bang = false, GvifmRange? range = null, string args = "") throws GvifmCommandError
    {
        if (this.check(bang, range)) {
            this._parent.statusbar.show_error(this.parse_args(args)[0]);
        }
        return 0;
    }

}

public class GvifmCommandEcho : GvifmCommand
{
    public GvifmCommandEcho(GvifmWindow window)
    {
        this._parent = window;
        this._num_args = GvifmCommandNargs.SINGLE;
        this.name = "ec[ho]";
    }

    public override int perform(bool bang = false, GvifmRange? range = null, string args = "") throws GvifmCommandError
    {
        if (this.check(bang, range))
        {
            this._parent.statusbar.show_message(this.parse_args(args)[0]);
        }
        return 0;
    }
}

public class GvifmCommandQuit : GvifmCommand
{
    public GvifmCommandQuit(GvifmWindow window)
    {
        this._parent = window;
        this._has_bang = true;
        this.name = "q[uit]";
    }

    public override int perform(bool bang = false, GvifmRange? range = null, string args = "") throws GvifmCommandError
    {
        if (this.check(bang, range))
        {
            this.parse_args(args);
            this._parent.destroy();
        }
        return 0;
    }
}

// 2}}}

// Commands collection {{{2

public class GvifmCommands
{
    private GLib.List<GvifmCommand> list;

    public GvifmCommands(GvifmWindow window)
    {
        list = new GLib.List<GvifmCommand>();
        list.append(new GvifmCommandQuit(window));
        list.append(new GvifmCommandEcho(window));
        list.append(new GvifmCommandEchoerr(window));
    }

    public GvifmCommand find_command(string name) throws GvifmCommandError.NotFound
    {
        foreach (GvifmCommand cmd in this.list)
        {
            stderr.printf("test cmd: %s\n", cmd.fullname);
            if (cmd.match_name(name))
            {
                return cmd;
            }
        }
        throw new GvifmCommandError.NotFound("E492: command not found: %s".printf(name));
    }

    public int execute(string command) throws GvifmCommandError
    {
        try {
            var re = new Regex("^(?:(\\.|(?:\\.[+-])?[0-9]+|'[a-z<>])(?:,((?:\\.[+-])?[0-9]+|'[a-z<>]))?)?([A-Za-z][A-Za-z0-9_]*)(\\!)?\\s*");
            MatchInfo matches;
            if (re.match(command, 0, out matches))
            {
                string[] match = matches.fetch_all();

                string name       = match[3];
                bool bang         = match[4] == "!";
                GvifmRange? range = null;
                string args       = "";

                stderr.printf("parsing: <%s>\n", match[3]);

                if (match[1] != "" || match[2] != "") {
                    range = GvifmRange();
                    range.firstline = match[1];
                    range.lastline  = match[2];
                }
                if (match[0].len() < command.len())
                    args = command.substring(match[0].len());
                return this.perform(name, bang, range, args);
            }
            else
            {
                stderr.printf("error parsing command\n");
            }
        } catch (RegexError e) {
            stderr.printf("command regex error: %s\n", e.message);
        }
        throw new GvifmCommandError.NotParseable("Error parsing command: %s\n".printf(command));
    }

    public int perform(string name, bool? bang = null, GvifmRange? range = null, string? args = null) throws GvifmCommandError
    {
        GvifmCommand cmd = this.find_command(name);
        stderr.printf("command found: %s -> %s\n", name, cmd.fullname);
        return cmd.perform(bang, range, args);
    }
}

// 2}}}

// }}}

// Command & status lines {{{

public class GvifmCommandLine : Gtk.Entry
{
    public GvifmCommandLine()
    {
        has_frame = false;
        hide();
    }
}

public class GvifmStatusbar : Gtk.HBox
{
    public Gtk.Label message;
    public GvifmCommandLine command_line;

    public GvifmStatusbar()
    {
        /*has_resize_grip = false;*/
        message = new Gtk.Label("");
        message.use_markup = true;
        command_line = new GvifmCommandLine();
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

public class GvifmMapping
{
    public GvifmMapping(string keyname)
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

    public signal int activate(int count = 0);
    /*public delegate int perform(int count = 0);*/
}

public class GvifmMappings
{
    private GLib.List<GvifmMapping> list;

    public GvifmMappings(GvifmWindow window)
    {
        GvifmMapping map;
        list = new GLib.List<GvifmMapping>();

        map = new GvifmMapping("colon");
        map.activate.connect((c) => { window.change_mode(GvifmMode.COMMAND); return 1; });
        list.append(map);

        map = new GvifmMapping("Q");
        map.activate.connect((c) => { window.execute_command("quit"); return 1; });
        list.append(map);
    }

    /*public static GvifmMapping make_mapping(string keyname, GvifmMapping.perform perform)*/
    /*{*/
        /*var result = new GvifmMapping(keyname);*/
        /*result.activate.connect(perform);*/
        /*return result;*/
    /*}*/

    public GvifmMapping? find_mapping(Gdk.EventKey key)
    {
        foreach (GvifmMapping map in this.list)
        {
            if (map.match_key(key))
            {
                return map;
            }
        }
        return null;
    }

    public int execute(Gdk.EventKey key)
    {
        GvifmMapping map = this.find_mapping(key);
        if (map != null) return map.activate(0);
        return 0;
    }
}

// }}}

public enum GvifmMode
{
    NORMAL,
    COMMAND,
    VISUAL,
    SEARCH,
}

public class GvifmFilesLoader
{
    private TreeIter? root_dir;
    private string root_dir_name;
    private GvifmFilesStore tree_store;

    private GLib.List<GvifmFilesLoader> subloaders;

    public GvifmFilesLoader(string dirname, GvifmFilesStore store)
    {
        store.append(out root_dir, null);
        store.set(root_dir, 0, dirname);
        root_dir = null;
        tree_store = store;
        root_dir_name = dirname;
    }

    public GvifmFilesLoader.from_iter(TreeIter root, string dirname, GvifmFilesStore store)
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
                    var subloader = new GvifmFilesLoader.from_iter(item, this.root_dir_name + "/" + finfo.get_name(), this.tree_store);
                    this.subloaders.append(subloader);
                    subloader.load_dir();
                }
            }
        }
    }
}

public class GvifmFilesStore : Gtk.TreeStore
{
    private GvifmFilesLoader loader;

    public GvifmFilesStore()
    {
        GLib.Type[] types = { typeof(string) };
        set_column_types(types);
    }

    public void load_dir(string dirname)
    {
        this.loader = new GvifmFilesLoader(dirname, this);
        this.loader.load_dir();
    }
}

public class GvifmTreeView : Gtk.IconView//Gtk.TreeView
{
    public ScrolledWindow scroller { get; private set; }

    public GvifmTreeView(GvifmFilesStore model)
    {
        set_model(model);
        /*insert_column_with_attributes(-1, "Filename", new CellRendererText(), "text", 0);*/

        scroller = new ScrolledWindow(null, null);
        scroller.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
        scroller.add(this);
    }

}

public class GvifmWindow : Gtk.Window
{
    [CCode (instance_pos=-1)]
    public bool normal_key_press_handler(Widget source, Gdk.EventKey key)
    {
        if (key.is_modifier == 0)
        {
            return this.mappings.execute(key) > 0;
        }
        return false;
    }

    [CCode (instance_pos=-1)]
    public bool command_key_press_handler(Widget source, Gdk.EventKey key)
    {
        if (key.keyval == 65293)
        {
            string cmd = this.statusbar.get_command_line();
            this.change_mode(GvifmMode.NORMAL);
            this.execute_command(cmd);
            return true;
        }
        return false;
    }

    public void change_mode(GvifmMode newmode)
    {
        this.mode = newmode;
        switch (newmode)
        {
            case GvifmMode.NORMAL:
                this.statusbar.close_command_line();
                this.key_press_event.disconnect(command_key_press_handler);
                this.key_press_event.connect(normal_key_press_handler);
            break;
            case GvifmMode.COMMAND:
                this.key_press_event.disconnect(normal_key_press_handler);
                this.key_press_event.connect(command_key_press_handler);
                this.statusbar.open_command_line(":");
            break;
            default:
            break;
        }
    }

    private GvifmMode mode = GvifmMode.NORMAL;
    public GvifmStatusbar statusbar;
    private GvifmCommands commands;
    private GvifmMappings mappings;

    private GvifmFilesStore fs_store;
    private GvifmTreeView fs_tree;

    private enum FsColumns
    {
        ICON,
        TITLE,
        NCOLS
    }

    public GvifmWindow()
    {
        this.title = "GVifm";
        this.destroy.connect(Gtk.main_quit);

        statusbar = new GvifmStatusbar();
        statusbar.command_line.focus_out_event.connect((src, ev) => { this.change_mode(GvifmMode.NORMAL); return false; });

        fs_store = new GvifmFilesStore();
        fs_tree = new GvifmTreeView(fs_store);

        var vbox = new VBox(false, 0);
        /*vbox.pack_start();*/
        vbox.pack_start(fs_tree.scroller, true, true, 0);
        vbox.pack_start(statusbar, false, false, 0);
        add(vbox);

        commands = new GvifmCommands(this);
        mappings = new GvifmMappings(this);
        change_mode(GvifmMode.NORMAL);

        fs_store.load_dir("/home/kstep/doc");
    }

    public int execute_command(string command)
    {
        try {
            return this.commands.execute(command);
        } catch (GvifmCommandError e) {
            this.statusbar.show_error(e.message);
        }
        return 0;
    }

    public static int main(string[] args)
    {
        Gtk.init(ref args);
        var window = new GvifmWindow();
        window.destroy.connect(Gtk.main_quit);
        window.show_all();
        Gtk.main();
        return 0;
    }
}

