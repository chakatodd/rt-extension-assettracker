# BEGIN LICENSE BLOCK
# 
#  Copyright (c) 2002-2003 Jesse Vincent <jesse@bestpractical.com>
#  
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of version 2 of the GNU General Public License 
#  as published by the Free Software Foundation.
# 
#  A copy of that license should have arrived with this
#  software, but in any event can be snarfed from www.gnu.org.
# 
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# 
# END LICENSE BLOCK

package RTx::AssetTracker;
use strict;
use warnings;
use version; our $VERSION = version->declare("2.0.0_4");

use RTx::AssetTracker::System;
use RTx::AssetTracker::Type;
use RTx::AssetTracker::Asset;
use RTx::AssetTracker::Templates;
use RTx::AssetTracker::Scrips;
use RTx::AssetTracker::ScripConditions;
use RTx::AssetTracker::ScripActions;

# Create a system object for AssetTracker
$RTx::AssetTracker::System = RTx::AssetTracker::System->new($RT::SystemUser);

RTx::AssetTracker::Type->ConfigureRoles();
RTx::AssetTracker::Asset->ConfigureLinks();

1;
