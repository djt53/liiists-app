package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(0)
	}

	cmd := os.Args[1]
	args := os.Args[2:]

	var err error
	switch cmd {
	case "init":
		err = cmdInit()
	case "new":
		err = cmdNew(args)
	case "add":
		err = cmdAdd(args)
	case "ls":
		err = cmdLs(args)
	case "rm":
		err = cmdRm(args)
	case "check":
		err = cmdCheck(args)
	case "help", "--help", "-h":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", cmd)
		printUsage()
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %s\n", err)
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Print(`liiists — dead-simple lists, backed by markdown

usage:
  liiists init                    set up your lists directory
  liiists new <name>              create a new list
  liiists add <list> <item>       add an item (or pipe stdin)
  liiists ls                      show all lists
  liiists ls <name>               show items in a list
  liiists rm <list> <item>        remove an item
  liiists check <list> <item>     toggle checkbox (checklists)
`)
}

// --- Commands ---

func cmdInit() error {
	dir, err := getListsDir()
	if err != nil {
		return err
	}

	// Check if already initialized
	if _, err := os.Stat(dir); err == nil {
		fmt.Printf("already initialized: %s\n", dir)
		return nil
	}

	// Ask for directory
	reader := bufio.NewReader(os.Stdin)
	fmt.Printf("where should lists live? [%s]: ", dir)
	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(input)

	if input != "" {
		home, _ := os.UserHomeDir()
		if strings.HasPrefix(input, "~/") {
			input = filepath.Join(home, input[2:])
		}
		dir = input

		// Save config
		configDir := filepath.Join(home, ".config", "liiists")
		os.MkdirAll(configDir, 0755)
		os.WriteFile(filepath.Join(configDir, "config"), []byte(fmt.Sprintf("lists_dir=%s\n", dir)), 0644)
	}

	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	fmt.Printf("initialized: %s\n", dir)

	// Offer to create first list
	fmt.Print("create your first list? [Y/n]: ")
	answer, _ := reader.ReadString('\n')
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer == "" || answer == "y" || answer == "yes" {
		fmt.Print("list name: ")
		name, _ := reader.ReadString('\n')
		name = strings.TrimSpace(name)
		if name != "" {
			return createList(dir, name, "list")
		}
	}

	return nil
}

func cmdNew(args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: liiists new <name> [--checklist]")
	}

	dir, err := getListsDir()
	if err != nil {
		return err
	}

	name := args[0]
	listType := "list"
	for _, a := range args[1:] {
		if a == "--checklist" || a == "-c" {
			listType = "checklist"
		}
	}

	return createList(dir, name, listType)
}

func createList(dir, name, listType string) error {
	slug := slugify(name)
	path := filepath.Join(dir, slug+".md")

	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("list already exists: %s", slug+".md")
	}

	l := &List{
		Title:   name,
		Type:    listType,
		Created: todayStr(),
		Path:    path,
		Extra:   make(map[string]string),
	}

	if err := l.Write(); err != nil {
		return err
	}

	fmt.Printf("created: %s\n", slug+".md")
	return nil
}

func cmdAdd(args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: liiists add <list> <item...>")
	}

	l, err := findList(args[0])
	if err != nil {
		return err
	}

	if len(args) >= 2 {
		// Items from arguments
		text := strings.Join(args[1:], " ")
		l.Items = append(l.Items, Item{Text: text})
		fmt.Printf("+ %s\n", text)
	} else {
		// Read from stdin
		stat, _ := os.Stdin.Stat()
		if (stat.Mode() & os.ModeCharDevice) == 0 {
			scanner := bufio.NewScanner(os.Stdin)
			for scanner.Scan() {
				text := strings.TrimSpace(scanner.Text())
				if text != "" {
					l.Items = append(l.Items, Item{Text: text})
					fmt.Printf("+ %s\n", text)
				}
			}
		} else {
			return fmt.Errorf("provide items as arguments or pipe via stdin")
		}
	}

	return l.Write()
}

func cmdLs(args []string) error {
	if len(args) == 0 {
		// List all lists
		lists, err := loadAllLists()
		if err != nil {
			return err
		}

		if len(lists) == 0 {
			fmt.Println("no lists yet — run 'liiists new <name>' to create one")
			return nil
		}

		for _, l := range lists {
			count := len(l.Items)
			if l.Type == "checklist" {
				checked := 0
				for _, item := range l.Items {
					if item.IsChecked {
						checked++
					}
				}
				fmt.Printf("  %s  %d/%d\n", l.Title, checked, count)
			} else {
				fmt.Printf("  %s  %d\n", l.Title, count)
			}
		}
		return nil
	}

	// Show specific list
	l, err := findList(args[0])
	if err != nil {
		return err
	}

	fmt.Printf("%s\n", l.Title)
	if len(l.Items) == 0 {
		fmt.Println("  (empty)")
		return nil
	}

	for _, item := range l.Items {
		if l.Type == "checklist" {
			if item.IsChecked {
				fmt.Printf("  [x] %s\n", item.Text)
			} else {
				fmt.Printf("  [ ] %s\n", item.Text)
			}
		} else {
			fmt.Printf("  %s\n", item.Text)
		}
	}
	return nil
}

func cmdRm(args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: liiists rm <list> <item text>")
	}

	l, err := findList(args[0])
	if err != nil {
		return err
	}

	search := strings.ToLower(strings.Join(args[1:], " "))
	found := false
	var remaining []Item
	for _, item := range l.Items {
		if !found && strings.ToLower(item.Text) == search {
			fmt.Printf("- %s\n", item.Text)
			found = true
			continue
		}
		remaining = append(remaining, item)
	}

	if !found {
		return fmt.Errorf("item not found: %s", strings.Join(args[1:], " "))
	}

	l.Items = remaining
	return l.Write()
}

func cmdCheck(args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: liiists check <list> <item text>")
	}

	l, err := findList(args[0])
	if err != nil {
		return err
	}

	if l.Type != "checklist" {
		return fmt.Errorf("'%s' is not a checklist", l.Title)
	}

	search := strings.ToLower(strings.Join(args[1:], " "))
	found := false
	for i, item := range l.Items {
		if strings.ToLower(item.Text) == search {
			l.Items[i].IsChecked = !l.Items[i].IsChecked
			if l.Items[i].IsChecked {
				fmt.Printf("[x] %s\n", item.Text)
			} else {
				fmt.Printf("[ ] %s\n", item.Text)
			}
			found = true
			break
		}
	}

	if !found {
		return fmt.Errorf("item not found: %s", strings.Join(args[1:], " "))
	}

	return l.Write()
}
