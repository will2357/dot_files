#!/bin/bash

set -e

script_dir="$(dirname "$(readlink -f "$0")")"
source "$script_dir/_shared_functions.sh"

if [ ! "$(uname)" == "Linux" ]; then prn_error "Must be on a debian based Linux system."; exit 1; fi

curr_dir=$PWD
home_dir=$HOME
temp_dir=/tmp/tmp_install
server="false"

# Switch to tmp dir
if pwd | grep -q /tmp_install$ ;then
    prn_note "Already in a tmp_install directory."
    temp_dir="$curr_dir"
else
    mkdir -p "$temp_dir"
    cd "$temp_dir" || exit 1
fi

# Get latest package lists
sudo apt update

# Don't bother with silly legal agreements on ubuntu-restricted-extras
export DEBIAN_FRONTEND=noninteractive
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
# Install basic requirements via apt
sudo apt install -y ack \
    autoconf \
    bash-completion \
    build-essential \
    checkinstall \
    curl  \
    git  \
    gh \
    htop \
    jq \
    libcurl3-gnutls \
    libcurl4-openssl-dev \
    libncurses5-dev \
    libreadline6-dev \
    libssl-dev \
    libxml2-dev \
    libxslt-dev \
    libyaml-dev \
    open-vm-tools \
    pkg-config \
    python-is-python3 \
    python3 \
    python3-dev \
    python3-pip \
    shellcheck \
    ssh \
    tmux  \
    ubuntu-restricted-addons \
    ubuntu-restricted-extras \
    unzip \
    xclip \
    zlib1g \
    zlib1g-dev

prn_success "Installed basic packages via apt."

prn_note "Installing universal-ctags from source."
compile_ctags () {
    cd "$temp_dir" || exit 1
    if which ctags
    then
        sudo apt purge -y exuberant-ctags
        sudo dpkg --purge --force-all exuberant-ctags
        sudo apt purge -y ctags
        sudo dpkg --purge --force-all ctags
    fi
    sudo rm -rf ctags
    git clone https://github.com/universal-ctags/ctags.git
    cd ctags
    ./autogen.sh
    ./configure
    make
    sudo checkinstall -y
    prn_success "Installed universal-ctags."
}
if ctags --version | grep Universal
then
    prn_note "Universal Ctags is already installed."
    resp=$(get_confirmation "Are you sure you wish to compile it from source?")
    if [ -n "$resp" ]
    then
        compile_ctags
    fi
else
    compile_ctags
fi

prn_note "Installing rbenv via rbenv-installer script."
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
prn_success "Installed rbenv."

prn_note "Installing nvm via nvm-sh installer script."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
prn_success "Installed nvm."

if [ -d "$HOME/.pyenv" ]; then rm -rf "$HOME/.pyenv" ;fi
prn_note "Installing pyenv via installer script."
curl https://pyenv.run | bash
prn_success "Installed pyenv."


if [ -z "$(which xset)" ]
then
    server="true"
fi

if [ "$server" != "true"  ]
then
    sudo apt -y install ddccontrol gddccontrol ddccontrol-db i2c-tools
fi

################################################################################
################### Thorium no longer actively maintained ######################
################################################################################
prn_note "Thorium web browser is no longer actively maintained."
resp=$(get_confirmation "Are you sure you wish to install Thorium?")
if [ -n "$resp" ]
then
    install_thorium () {
        thorium_deb=$(curl -s https://api.github.com/repos/Alex313031/Thorium/releases/latest | jq -r '.assets[0].browser_download_url')
        wget "$thorium_deb"
        sudo dpkg -i thorium-browser*.deb
    }
    if [ -z "$(which thorium-browser)" ]
    then
        if [ "$server" == "true" ]
        then
            resp=$(get_confirmation "You appear to be on a server. Do you wish to install 'thorium-browser'?")
            if [ -n "$resp" ]
            then
                install_thorium
            fi
        else
            install_thorium
        fi
    else
        prn_note "'thorium-browser' already installed. Skipping."
    fi
    if which thorium-browser
    then
        BROWSER="$(which thorium-browser)"
        export BROWSER
    fi
fi

prn_note "Configuring git."

if ! git config user.name
then
    git_user_name=""
    get_input "Enter git user.name (blank for default of 'will2357'): " \
        git_user_name "will2357"
    git config --global user.name "$git_user_name"
fi

if ! git config user.email
then
    git_user_email=""
    get_input "Enter git user.email (blank for default of 'will@highducheck.org'): " \
        git_user_email "will@highducheck.org"
    git config --global user.email "$git_user_email"
fi

git config --global push.default simple
git config --global color.ui auto
git config --global core.excludesfile "$home_dir/.gitignore_global"
git config --global core.editor vim
git config --global merge.tool vim

if ! gh auth status; then
    gh auth login
fi

src_dir="$home_dir/src"
printf "Changing directory to '%s'" "$src_dir"
mkdir -p "$src_dir"
cd "$src_dir" || exit 1

compile_vim () {
    prn_note "Compiling vim from source."
    sudo apt purge -y vim
    sudo dpkg --purge --force-all vim
    cd "$src_dir" || exit 1
    sudo rm -rf vim
    git clone https://github.com/vim/vim.git
    cd vim/src/ || exit 1
    if grep ubuntu.sources /etc/apt/sources.list; then
        if ! grep deb-src /etc/apt/sources.list.d/ubuntu.sources; then
            echo "
Types: deb-src
URIs: http://us.archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports noble-proposed
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" | sudo tee -a  /etc/apt/sources.list.d/ubuntu.sources
        fi
    else
        sudo sed -i 's/\#\ deb\-src/deb-src/g' /etc/apt/sources.list
    fi
    sudo apt update
    sudo apt build-dep -y vim
    sudo ./configure --with-features=huge --enable-multibyte \
        --enable-rubyinterp=yes --enable-python3interp=yes \
        --with-python3-config-dir="$(python3-config --configdir)" \
        --enable-perlinterp=yes --enable-luainterp=yes --enable-gui=gtk2 \
        --enable-cscope --enable-gui --with-x
    sudo make
    sudo make install
    prn_success "Finished compiling vim from source."
}

installed_vv=""
if which vim
then
    installed_vv=$(vim --version 2>&1 | awk 'FNR == 1 {print $5}' |  grep -P -o "[0-9]+\.[0-9]+")
fi
latest_vv=$(curl -s https://api.github.com/repos/vim/vim/tags | grep "name.*v" | awk 'FNR == 1 {print $2}' | grep -P -o "[0-9]+\.[0-9]+")

if [ "$latest_vv" == "$installed_vv" ]
then
    prn_note "Latest version ($latest_vv) of vim already installed."
    resp=$(get_confirmation "Are you sure you wish to continue?")
    if [ -n "$resp" ]
    then
        compile_vim
    fi
else
    compile_vim
fi

cd "$src_dir" || exit 1

if [ ! -d "$src_dir/dot_files" ]; then
    git clone https://github.com/will2357/dot_files.git "$src_dir/dot_files"
fi
cd dot_files || exit 1
if [ "$(git branch -l | grep linux | awk '{print $2}')" ]; then
    prn_note "Using linux branch in dot_files repo."
    git checkout linux
else
    prn_note "No branch named linux in dot_files repo. Using master."
fi

prn_note "Running 'dot_install.sh' script with default options."

chmod +wrx "$script_dir/dot_install.sh"
"$script_dir/dot_install.sh"

cd "$src_dir" || exit 1

if which vim
then
    prn_note "Installing vim plugins."
    vim_plug="$home_dir/.vim/autoload/plug.vim"
    if [ ! -f "$vim_plug" ]; then
        prn_note "Installing 'vim-plug'."
        curl -fLo "$vim_plug" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    fi

    vim_solar_dir="$home_dir/.vim/bundle/vim-colors-solarized"
    if [ ! -d "$vim_solar_dir" ]; then
        git clone https://github.com/altercation/vim-colors-solarized.git "$vim_solar_dir"
    fi
    vim +'PlugInstall --sync' +qa
fi

cd "$curr_dir" || exit 1

tmux_plugin_man_dir="$home_dir/.tmux/plugins/tpm"
if [ ! -d "$tmux_plugin_man_dir" ];then
    prn_note "Installing tpm for tmux."
    git clone https://github.com/tmux-plugins/tpm "$tmux_plugin_man_dir"
fi
# start a server but don't attach to it
tmux start-server
# create a new session but don't attach to it either
tmux new-session -d
prn_note "Installing tmux plugins."
"$tmux_plugin_man_dir/scripts/install_plugins.sh"

# Install AWS CLI
# Remove yum and apt versions of AWS CLI if exist
if which yum; then sudo yum remove awscli; fi
sudo apt purge awscli
cd "$temp_dir" || exit 1

prn_note "Installing AWS CLI from AmazonAWS.com."
if which aws
then
    prn_note "AWS CLI already installed."
    resp=$(get_confirmation "Do you wish to update the AWS CLI?")

    if [ -n "$resp" ]
    then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        sudo ./aws/install --update
        prn_success "Updated AWS CLI."
    fi
else
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    prn_success "Installed AWS CLI."
fi

# Install Terraform CLI
if which terraform
then
    prn_note "Terraform CLI already installed."
else
    prn_note "Installing Terraform CLI."
    cd "$temp_dir" || exit 1
    wget -O- https://apt.releases.hashicorp.com/gpg | \
        sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install terraform
    prn_success "Installed Terraform CLI."
fi

# Cleanup
cd "$home_dir" || exit 1
sudo rm -rf "$temp_dir"

prn_success "SUCCESS: Ran 'clean_install.sh' script without errors."

prn_note "NOTE:
On desktop install, change terminal colors to solarized dark by going to
the GNOME terminal menu ->
'Preferences' -> 'Profiles|Unnamed' -> 'Colors' ->
Uncheck 'Use colors from system theme'
Select 'Solarized dark' from 'Built-in schemes' in both 'Text and Background' and 'Palette'"

exit 0
