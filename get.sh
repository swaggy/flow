#!/bin/sh

dir=${TMPDIR:-/tmp}

echo "Using $dir as the working directory"
cd $dir

echo "Downloading flow.sh"
wget -q https://raw.githubusercontent.com/swaggy/flow/master/flow.sh

files="$dir/flow.sh"
trap "rm -f $files" EXIT

commands="lib async await group"
for command in $commands; do
    echo "Downloading $command command."
    wget -q https://raw.githubusercontent.com/swaggy/flow/master/commands/$command.sh
    files="$files $dir/$command.sh"
    trap "rm -f $files" EXIT
done

echo "Installing flow into /usr/local/bin/flow"
chmod +x flow.sh
if [ -w /usr/local/bin ]; then
    mv flow.sh /usr/local/bin/flow
else
    sudo mv flow.sh /usr/local/bin/flow
fi

for command in $commands; do
    dest="/usr/local/bin/.flow-$command"
    echo "Installing command $command into $dest"
    chmod +x $command.sh
    if [ -w /usr/local/bin ]; then
        mv $command.sh $dest
    else
        sudo mv $command.sh $dest
    fi
done
