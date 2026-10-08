#!/usr/bin/env python3
"""Add vim keys to duc's ncurses browser (src/duc/cmd-ui.c), across duc 1.4.x.

j/k move · h/l parent/enter · g/G top/bottom · ctrl-f/b page · v graph toggle
(was g) · ? help (h freed) · o reveals the item (macOS `open -R`, else xdg-open) ·
i info popup (path, on-disk/apparent size, file count, live modified/owner/mode).
Usage: duc_vim_patch.py path/to/cmd-ui.c [--macos]
"""
import re
import sys

path, macos = sys.argv[1], "--macos" in sys.argv
s = open(path).read()
if "/* vim-keys */" in s:
    sys.exit("already patched")


def rep(old, new, required=True):
    global s
    if old not in s:
        if required:
            sys.exit(f"pattern not found: {old!r}")
        return
    s = s.replace(old, new, 1)


rep("\t\t\tcase 4: cur += pgsize/2; break;\n",
    "\t\t\tcase 4: cur += pgsize/2; break;\n"
    "\t\t\tcase 6: cur += pgsize; break;   /* vim-keys */ /* ctrl-f */\n"
    "\t\t\tcase 2: cur -= pgsize; break;   /* ctrl-b */\n")
rep("\t\t\tcase '0': cur = 0; break;\n", "\t\t\tcase 'g':\n\t\t\tcase '0': cur = 0; break;\n")
rep("\t\t\tcase '$': cur = count-1; break;\n", "\t\t\tcase 'G':\n\t\t\tcase '$': cur = count-1; break;\n")
rep("\t\t\tcase 'g': opt_graph ^= 1; break;\n", "\t\t\tcase 'v': opt_graph ^= 1; break;\n")
rep("\t\t\tcase 'h': help(); break;\n", "")
if "case '?': help(); break;" not in s:
    rep("\t\t\tcase 'n': opt_name_sort ^= 1; break;\n",
        "\t\t\tcase '?': help(); break;\n\t\t\tcase 'n': opt_name_sort ^= 1; break;\n")
rep("\t\t\tcase KEY_BACKSPACE:\n", "\t\t\tcase 'h':\n\t\t\tcase KEY_BACKSPACE:\n")
rep("\t\t\tcase KEY_RIGHT:\n", "\t\t\tcase 'l':\n\t\t\tcase KEY_RIGHT:\n")
if macos:
    rep('"xdg-open \\"%s/%s\\""', '"open -R \\"%s/%s\\""', required=False)

# Help text: replace from the first key line through the quit line.
m = re.search(r'\t\t"    up, pgup, j:.*?"    q, escape: +quit\\n"\n', s, re.S)
if not m:
    sys.exit("help text not found")
opener = "reveal the selected item in Finder" if macos else "open the selected item (xdg-open)"
lines = [
    ("k, up", "move cursor up"), ("j, down", "move cursor down"),
    ("ctrl-u / ctrl-d", "half page up / down"), ("ctrl-b / ctrl-f", "page up / down (also pgup / pgdn)"),
    ("g, 0, home", "move cursor to top"), ("G, $, end", "move cursor to bottom"),
    ("h, left, backspace", "go up to parent directory (..)"),
    ("l, right, enter", "descend into selected directory"),
    ("a", "toggle between actual and apparent disk usage"),
    ("b", "toggle between exact and abbreviated sizes"),
    ("c", "toggle between file size and file count"), ("v", "toggle the size graph"),
    ("n", "toggle sort order between 'size' and 'name'"), ("o", opener),
    ("i", "info: path, sizes, file count, modified, owner"),
    ("?", "show this help ('q' returns)"), ("q, escape", "quit"),
]
help_text = "".join(f'\t\t"    {k + ":":<20}{v}\\n"\n' for k, v in lines)
s = s[:m.start()] + help_text + s[m.end():]

# --- i: info popup for the selected entry --------------------------------------
rep("#include <locale.h>\n", "#include <locale.h>\n#include <grp.h>\n#include <pwd.h>\n#include <time.h>\n")
INFO_FN = r"""
/* vim-keys: info popup for the selected entry. Returns the key that closed it. */
static int info_popup(duc_dir *dir, int cur, duc_size_type st, duc_sort sort)
{
	duc_dir_seek(dir, cur);
	struct duc_dirent *e = duc_dir_read(dir, st, sort);
	if(!e) return 0;
	char *base = duc_dir_get_path(dir);
	static char path[DUC_PATH_MAX];
	snprintf(path, sizeof path, "%s/%s", base ? base : "", e->name);
	free(base);

	char act[32], app[32], cnt[32];
	duc_human_size(&e->size, DUC_SIZE_TYPE_ACTUAL, 0, act, sizeof act);
	duc_human_size(&e->size, DUC_SIZE_TYPE_APPARENT, 0, app, sizeof app);
	duc_human_size(&e->size, DUC_SIZE_TYPE_COUNT, 0, cnt, sizeof cnt);
	const char *type = e->type == DUC_FILE_TYPE_DIR ? "directory" :
	                   e->type == DUC_FILE_TYPE_REG ? "file" :
	                   e->type == DUC_FILE_TYPE_LNK ? "symlink" : "other";

	static char line[12][1024];
	int n = 0;
	snprintf(line[n++], sizeof line[0], "Name      %s", e->name);
	snprintf(line[n++], sizeof line[0], "Path      %s", path);
	snprintf(line[n++], sizeof line[0], "Type      %s", type);
	snprintf(line[n++], sizeof line[0], "On disk   %sB   (apparent %sB)", act, app);
	if(e->type == DUC_FILE_TYPE_DIR)
		snprintf(line[n++], sizeof line[0], "Files     %s", cnt);
	struct stat sb;
	if(lstat(path, &sb) == 0) {
		char when[64];
		strftime(when, sizeof when, "%Y-%m-%d %H:%M", localtime(&sb.st_mtime));
		struct passwd *pw = getpwuid(sb.st_uid);
		struct group *gr = getgrgid(sb.st_gid);
		snprintf(line[n++], sizeof line[0], "Modified  %s", when);
		snprintf(line[n++], sizeof line[0], "Owner     %s:%s   mode %04o",
		         pw ? pw->pw_name : "?", gr ? gr->gr_name : "?", (unsigned)(sb.st_mode & 07777));
	} else {
		snprintf(line[n++], sizeof line[0], "Now       %s",
		         errno == ENOENT ? "no longer exists (the index is older)" : strerror(errno));
	}
	snprintf(line[n++], sizeof line[0], "%s", "");
	snprintf(line[n++], sizeof line[0], "%s", "o: reveal    any other key: close");

	int w = 0;
	for(int i = 0; i < n; i++) { int l = (int)strlen(line[i]); if(l > w) w = l; }
	w += 4;
	if(w > cols - 2) w = cols - 2;
	if(w < 24) w = 24;
	int h = n + 2;
	if(h > rows) h = rows;
	WINDOW *win = newwin(h, w, (rows - h) / 2, (cols - w) / 2);
	if(!win) return 0;
	box(win, 0, 0);
	mvwaddstr(win, 0, 2, " Info ");
	int room = w - 4;
	for(int i = 0; i < n && i < h - 2; i++) {
		int l = (int)strlen(line[i]);
		if(l > room && strncmp(line[i], "Path", 4) == 0) {
			/* keep the end of a long path, which is the informative part */
			mvwaddstr(win, i + 1, 2, "Path      ...");
			mvwaddnstr(win, i + 1, 15, line[i] + l - (room - 13), room - 13);
		} else {
			mvwaddnstr(win, i + 1, 2, line[i], room);
		}
	}
	wrefresh(win);
	int c = wgetch(win);
	delwin(win);
	touchwin(stdscr);
	refresh();
	return c;
}

"""
rep("static duc_dir *do_dir(", INFO_FN + "static duc_dir *do_dir(")   # signature differs across versions
rep("\t\t\tcase '?': help(); break;\n",
    "\t\t\tcase '?': help(); break;\n"
    "\t\t\tcase 'i': if(info_popup(dir, cur, st, sort) == 'o') ungetch('o'); break;\n")
open(path, "w").write(s)
print("patched", path)
