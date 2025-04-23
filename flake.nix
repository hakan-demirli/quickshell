{
  description = "Ephemeral fzf, yazi, bat, tmux, starship, aliases, and configured Bash/Helix shell integration via nix shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dotfiles-src = {
      url = "github:hakan-demirli/dotfiles";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      dotfiles-src,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        fzf-share-dir = "${pkgs.fzf}/share/fzf";

        yazi-config-dir = "${dotfiles-src}/.config/yazi";
        helix-config-dir = "${dotfiles-src}/.config/helix";
        bat-config-file = "${dotfiles-src}/.config/bat/config";
        tmux-config-file = "${dotfiles-src}/.config/tmux/tmux.conf";
        starship-config-file = "${dotfiles-src}/.config/starship.toml";
        dotfiles-local-bin = "${dotfiles-src}/.local/bin";

        helixWrapped =
          pkgs.runCommand "helix-wrapped"
            {
              nativeBuildInputs = [ pkgs.makeWrapper ];
              buildInputs = [ pkgs.helix ];
              meta = pkgs.helix.meta // {
                description = "Helix editor wrapped with custom config from dotfiles";
              };
            }
            ''
              mkdir -p $out/bin
              makeWrapper ${pkgs.helix}/bin/hx $out/bin/hx \
                --add-flags "--config ${helix-config-dir}/config.toml"

            '';

        tmuxWrapped = pkgs.writeShellScriptBin "tmux" ''
          #!${pkgs.runtimeShell}
          if [ ! -f "${tmux-config-file}" ]; then
              echo "Warning: tmux config file not found at '${tmux-config-file}'." >&2
          fi
          exec ${pkgs.tmux}/bin/tmux -f "${tmux-config-file}" "$@"
        '';

        dotfilesScripts =
          pkgs.runCommand "dotfiles-local-bin-scripts"
            {
              nativeBuildInputs = [ pkgs.coreutils ];
              meta = {
                description = "Custom scripts from hakan-demirli/dotfiles .local/bin";
              };
            }
            ''
              mkdir -p $out/bin
              if [ -d "${dotfiles-local-bin}" ]; then
                
                find "${dotfiles-local-bin}" -maxdepth 1 -type f -executable -exec cp {} $out/bin/ \; || echo "Warning: Could not copy some scripts from ${dotfiles-local-bin}"
                echo "Scripts copied from ${dotfiles-local-bin}."
              else
                echo "Warning: Script directory ${dotfiles-local-bin} not found. Skipping script packaging."
              fi
            '';

        fzfDefaultCommand = "${pkgs.fd}/bin/fd --type f";
        fzfDefaultOptionsList = [
          "--bind 'tab:toggle-up,btab:toggle-down'"
          "--info=inline"
          "--border"
          "--color=fg:-1,bg:-1,hl:#bd93f9"
          "--color=fg+:#f8f8f2,bg+:#282a36,hl+:#bd93f9"
          "--color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6"
          "--color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"
          "--prompt='❯ '"
        ];
        fzfDefaultOptsString = pkgs.lib.strings.concatStringsSep " " fzfDefaultOptionsList;

        bashHistControl = pkgs.lib.strings.concatStringsSep ":" [
          "ignoredups"
          "erasedups"
        ];

        fontsConf = pkgs.makeFontsConf {
          fontDirectories = [ pkgs.nerd-fonts.jetbrains-mono ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "integrated-dev-shell";

          nativeBuildInputs = [

            pkgs.bashInteractive
            pkgs.fzf
            pkgs.yazi
            pkgs.fd
            pkgs.bat
            pkgs.starship
            pkgs.git

            helixWrapped
            tmuxWrapped

            dotfilesScripts

            pkgs.ffmpegthumbnailer
            pkgs.unar
            pkgs.jq
            pkgs.ripgrep
            pkgs.direnv
            pkgs.difftastic
            pkgs.yarn
            pkgs.wget
            pkgs.coreutils
          ];

          buildInputs = [
            pkgs.difftastic
          ];

          HISTSIZE = "-1";
          HISTFILESIZE = "-1";
          HISTCONTROL = bashHistControl;
          FZF_DEFAULT_COMMAND = fzfDefaultCommand;
          FZF_DEFAULT_OPTS = fzfDefaultOptsString;
          YAZI_CONFIG_HOME = yazi-config-dir;
          BAT_CONFIG_PATH = bat-config-file;
          STARSHIP_CONFIG = starship-config-file;
          FONTCONFIG_FILE = "${fontsConf}/etc/fonts/fonts.conf"; # Use generated font config

          shellHook = ''
            echo "--- Setting up integrated shell environment ---"


            if [ ! -f "${starship-config-file}" ]; then
                echo "INFO: Starship config '${starship-config-file}' not found. Using defaults." >&2
                unset STARSHIP_CONFIG
            fi

            current_shell=$(basename "$SHELL")


            if [[ "$current_shell" = "bash" ]]; then
              echo "[Bash] Configuring integrations..."
              
              export PROMPT_COMMAND="history -a; history -r; $PROMPT_COMMAND"
              
              [[ -f "${fzf-share-dir}/key-bindings.bash" ]] && source "${fzf-share-dir}/key-bindings.bash"
              [[ -f "${fzf-share-dir}/completion.bash" ]] && source "${fzf-share-dir}/completion.bash"
              
              if command -v starship > /dev/null; then eval "$(starship init bash)"; else echo "WARN: starship not found."; fi
            elif [[ "$current_shell" = "zsh" ]]; then
              echo "[Zsh] Configuring integrations..."
              
              [[ -f "${fzf-share-dir}/key-bindings.zsh" ]] && source "${fzf-share-dir}/key-bindings.zsh"
              [[ -f "${fzf-share-dir}/completion.zsh" ]] && source "${fzf-share-dir}/completion.zsh"
              
              if command -v starship > /dev/null; then eval "$(starship init zsh)"; else echo "WARN: starship not found."; fi
            else
              echo "WARN: Unsupported shell '$current_shell' for FZF/Starship integration."
            fi


            yazi_cd() {
              local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
              if ! command -v yazi >/dev/null 2>&1; then echo "ERROR: yazi command not found." >&2; rm -f -- "$tmp"; return 1; fi
              yazi --cwd-file="$tmp" "$@"
              local yazi_status=$?
              if [ "$yazi_status" -ne 0 ]; then rm -f -- "$tmp"; return "$yazi_status"; fi 
              if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then cd -- "$cwd"; fi
              rm -f -- "$tmp"
            }
            export YAZI_CONFIG_HOME="${yazi-config-dir}" 
            echo "INFO: yazi_cd function defined. YAZI_CONFIG_HOME set."


            echo "INFO: BAT_CONFIG_PATH set to '${bat-config-file}'."


            echo "INFO: 'hx' command available (wrapped)."


            echo "INFO: 'tmux' command available (wrapped with config '${tmux-config-file}')."


            if [ -n "$STARSHIP_CONFIG" ]; then
               echo "INFO: Starship using config '${starship-config-file}'."
            else
               echo "INFO: Starship using default config."
            fi


            if [ -d "${dotfilesScripts}/bin" ] && [ -n "$(ls -A ${dotfilesScripts}/bin)" ]; then
                echo "INFO: Custom scripts from dotfiles added to PATH."
            else
                echo "INFO: No custom scripts found or packaged from dotfiles."
            fi


            echo "INFO: Defining shell aliases..."
            alias :q='exit'
            alias q:='exit'
            alias :wq='exit'
            alias hx.='hx .'
            alias ..='cd ..'
            alias c='clear'
            alias cd..='cd ..'
            alias helix='hx' 
            alias lf='echo "Did you mean f (yazi_cd)?"'
            alias f='yazi_cd'
            alias ff='yazi_cd'
            alias cdf='cd "$(find . -type d | fzf)"' 
            alias da='direnv allow' 

            alias ga.='git add .'
            alias ga='git add'
            alias gd='git -c diff.external=difft diff' 
            alias gdc='git -c diff.external=difft diff --cached' 
            alias gp='git push'
            alias gpf='git push --force'
            alias gr='git restore'
            alias gr.='git restore .'
            alias grs='git restore --staged'
            alias gs='git status'

            alias gc='git commit'
            alias gcm='git commit -m '
            alias gca='git commit --amend'

            alias yarn='yarn --use-yarnrc "$XDG_CONFIG_HOME/yarn/config"' 

            alias txa='tmux attach-session -t $(tmux list-sessions -F "#{session_name}" | head -n 1)' 
            alias txls='tmux list-sessions'
            alias txks='tmux kill-session -t '
            alias txn='tmux new-session -s'
            alias txs='tmux switch-client -n'
            alias txkw='tmux kill-window -t '
            alias txlw='tmux list-windows'
            alias wget='wget --hsts-file="$XDG_DATA_HOME/wget-hsts"' 


            echo "--- Shell setup complete. Enjoy! ---"
            unset current_shell 
          '';
        };
      }
    );
}
