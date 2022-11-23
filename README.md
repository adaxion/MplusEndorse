# M+ Endorse

M+ Endorse is a World of Warcraft (WoW) addon designed to keep track of your M+ runs and allow you to endorse, positively or negatively, the players that you group with. Additionally, you're able to share endorsements with guild members, friends, and party members. Tracking this data is aimed at providing you a way to find people that you want to group with who have been positively endorsed by you and those you trust... or to avoid players that get a lot of negative endorsements.

This document is intended for _developers_ wishing to write code for the M+ Endorse addon. If you're looking for more information on how to install this addon and use it in game please check out https://adaxion.github.io/MplusEndorse. Readers should have familiarity with Lua and WoW addon development. Links to reference material for Lua, WoW, and libraries used in this addon can be found at the bottom of this document.

## Installing Codebase

We recommend installing this codebase with git from the GitHub repo found at https://github.com/adaxion/MplusEndorse. Please follow the OS specific instructions for completing this step.

## Overview

This Addon is largely split into two components, `src/Main.lua`, and `src/UI.lua`. Main is responsible for the domain logic and providing the glue code for [Ace 3.0]() libraries that provide common or useful functionality. The design was intentionally setup in such a way to avoid exposing as many globals as possible. Main does not know of any components or functions available in UI and vice versa; they communicate appropriate information with one another through the [AceEvent]() library. In fact, the only globals we explicitly expose are in the aptly named `src/Globals.lua` file. Generally speaking, any changes to this addon that require more globals should be carefully considered and added to this file when appropriate.

The minimum working state of the addon is that at the end of every M+ run, successful or failure, a window is displayed that allows you to give each party member an endorsement score. This score can be a +1 or a -1, can be applied to every party member in the M+ run, and can only be given once per run. After endorsements have been made you can later see that information by typing the console command `/mpe`.