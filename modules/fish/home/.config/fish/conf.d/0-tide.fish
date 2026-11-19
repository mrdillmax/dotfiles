# Tide prompt repair.
#
# Tide keeps its configuration in universal variables written by
# `tide configure`. A fresh fisher install seeds the lean preset, so this file
# does not copy any prompt settings.
#
# An older dotfiles version exported fish_variables through `string escape`.
# Empty values became literal quotes, and Tide then ran
# `string shorten -''m24` on every prompt. Remove those broken values so the
# preset from `tide configure` (or Tide's default) applies again.

if set -q tide_cmd_duration_icon
    if contains -- "''" $tide_cmd_duration_icon; or contains -- "'" $tide_cmd_duration_icon
        set -e -U tide_cmd_duration_icon
    end
end

if set -q tide_git_icon
    if contains -- "''" $tide_git_icon; or contains -- "'" $tide_git_icon
        set -e -U tide_git_icon
    end
end

if set -q tide_git_truncation_strategy
    if contains -- "''" $tide_git_truncation_strategy; or contains -- "'" $tide_git_truncation_strategy
        set -e -U tide_git_truncation_strategy
    end
end

if set -q tide_pwd_icon
    if contains -- "''" $tide_pwd_icon; or contains -- "'" $tide_pwd_icon
        set -e -U tide_pwd_icon
    end
end

if set -q tide_pwd_icon_home
    if contains -- "''" $tide_pwd_icon_home; or contains -- "'" $tide_pwd_icon_home
        set -e -U tide_pwd_icon_home
    end
end
