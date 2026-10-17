# ai-login: sign Codex and Claude in from your phone, then hand this machine
# to the phone through Claude Remote Control. Nothing is stored on the
# stick: a live session forgets the logins at shutdown.

work="$HOME/rescue"
qr() { qrencode -t ansiutf8 -m 2 "$1"; }

# both CLIs need the internet; USB tethering needs no drivers or passwords
until curl -s -o /dev/null --max-time 5 https://api.anthropic.com; do
  echo "No internet yet. Plug in your phone and turn on USB tethering, or run nmtui for Wi-Fi. Retrying..."
  sleep 5
done

# codex: device-code login, nothing to type back here
if codex login status >/dev/null 2>&1; then
  echo "Codex: already signed in."
else
  echo
  echo "== Codex: scan this, sign in, then enter the code printed below it"
  qr https://auth.openai.com/codex/device
  codex login --device-auth || echo "Codex sign-in didn't finish; run 'codex login --device-auth' to retry."
fi

# claude: its printed URL ends at a page showing a code that must come back
# to this terminal, so run the login in tmux and type the code into it
if claude auth status >/dev/null 2>&1; then
  echo "Claude: already signed in."
else
  sock=ai-login
  nobrowser=$(mktemp -d)
  ln -s "$(command -v true)" "$nobrowser/xdg-open"
  tmux -L "$sock" kill-server 2>/dev/null || true
  tmux -L "$sock" new-session -d -s login -x 250 -y 50 \
    "PATH='$nobrowser:$PATH' BROWSER=true claude auth login"

  url=""
  for _ in $(seq 60); do
    url=$(tmux -L "$sock" capture-pane -p -J -t login 2>/dev/null |
      grep -o 'visit: https://[^ ]*' | head -1 | cut -c8-) || true
    [[ -n $url ]] && break
    sleep 1
  done
  if [[ -z $url ]]; then
    echo "Couldn't read Claude's login URL. Run 'claude auth login' by hand." >&2
    tmux -L "$sock" kill-server 2>/dev/null || true
    exit 1
  fi

  echo
  echo "== Claude, step 1: scan this and sign in on your phone"
  qr "$url"
  echo "== Claude, step 2: it shows a code. Scan the next QR code to send it here, or type it and press Enter."
  code_file=$(mktemp)
  phone-paste >"$code_file" &
  pp=$!
  while kill -0 "$pp" 2>/dev/null; do
    if read -r -t 1 typed && [[ -n $typed ]]; then
      echo "$typed" >"$code_file"
      kill -TERM "$pp" 2>/dev/null || true
      break
    fi
  done
  wait "$pp" 2>/dev/null || true

  code=$(<"$code_file")
  if [[ -n $code ]]; then
    tmux -L "$sock" send-keys -t login -l "$code"
    tmux -L "$sock" send-keys -t login Enter
  fi
  for _ in $(seq 30); do
    tmux -L "$sock" has-session -t login 2>/dev/null || break
    sleep 1
  done
  tmux -L "$sock" kill-server 2>/dev/null || true
  rm -rf "$nobrowser" "$code_file"

  if ! claude auth status >/dev/null 2>&1; then
    echo "Claude sign-in didn't finish; run 'ai-login' again, or 'claude auth login' by hand." >&2
    exit 1
  fi
  echo "Claude: signed in."
fi

echo
echo "== Starting Claude Remote Control in $work."
echo "   Press space for its QR code, scan it, and drive this machine from the Claude app."
cd "$work"
exec claude remote-control --name "rescue-$(hostname)"
