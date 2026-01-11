# Create .coder/ folder if does not exist
mkdir -p .coder
# Create .coder/settings.json with default settings if it does not exist
if [ ! -f .coder/settings.json ]; then
  cat <<EOL > .coder/settings.json
  {
    "editor.fontSize": 14,
    "editor.tabSize": 2,
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "terminal.integrated.fontSize": 14,
    "workbench.colorTheme": "Default Dark+"
  }
EOL
fi

# Add the .coder/ folder to .gitignore if not already present
if ! grep -q "^.coder/$" .gitignore; then
  echo ".coder/" >> .gitignore
fi

# Add the ./**/*.coder.* files to .gitignore if not already present
if ! grep -q "^.*/\.coder/.*$" .gitignore; then
  echo ".*/.coder/.*" >> .gitignore
fi
