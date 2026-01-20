return {
    timeout = 10000,
    maxSpikes = 5,
    policePlatePrefix = 'LSPD',
    objects = {
        cone = {model = `prop_roadcone02a`, freeze = false},
        barrier = {model = `prop_barrier_work06a`, freeze = true},
        roadsign = {model = `prop_snow_sign_road_06g`, freeze = true},
        tent = {model = `prop_gazebo_03`, freeze = true},
        light = {model = `prop_worklight_03b`, freeze = true},
        chair = {model = `prop_chair_08`, freeze = true},
        chairs = {model = `prop_chair_pile_01`, freeze = true},
        tabe = {model = `prop_table_03`, freeze = true},
        monitor = {model = `des_tvsmash_root`, freeze = true},
    },

    locations = {
        duty = {
            vec3(199.2711, -807.0460, 31.0722),
            --vec3(-449.811, 6012.909, 31.815),
        },
        vehicle = {
            vec4(452.0, -996.0, 26.0, 175.0),
            vec4(447.0, -997.0, 26.0, 178.0),
            vec4(463.0, -1019.0, 28.0, 87.0),
            vec4(463.0, -1015.0, 28.0, 87.0),
        },
        stash = { -- Not currently used, use ox_inventory stashes
            -- vec3(453.075, -980.124, 30.889),
        },
        impound = {
            vec3(416.91, -1627.71, 29.29),
            --vec3(-436.14, 5982.63, 31.34)
        },
        helicopter = {
            --vec4(448.3857, -981.0323, 43.6913, 268.1711),
            --vec4(-475.43, 5988.353, 31.716, 31.34),
        },
        armory = { -- Not currently used, use ox_inventory shops
            -- vec3(462.23, -981.12, 30.68),
        },
        trash = {
            --vec3(484.24, -984.16, 29.69),
        },
        fingerprint = {
            --vec3(483.77, -987.92, 29.69),
        },
        evidence = { -- Not currently used, use ox_inventory evidence system
        },
        stations = {
            {label = 'Mission Row Police Station', coords = vec3(381.38, -1592.86, 30.05)},
            --{label = 'Sandy Shores Police Station', coords = vec3(1853.4, 3684.5, 34.3)},
            -- {label = 'Vinewood Police Station', coords = vec3(637.1, 1.6, 81.8)},
            -- {label = 'Vespucci Police Station', coords = vec3(-1092.6, -808.1, 19.3)},
            -- {label = 'Davis Police Station', coords = vec3(368.0, -1618.8, 29.3)},
            -- {label = 'Paleto Bay Police Station', coords = vec3(-448.4, 6011.8, 31.7)},
        },
    },

    radars = {
        -- /!\ The maxspeed(s) need to be in an increasing order /!\
        -- If you don't want to fine people just do that: 'config.speedFines = false'
        -- fine if you're maxspeed or less over the speedlimit
        -- (i.e if you're at 41 mph and the radar's limit is 35 you're 6mph over so a 25$ fine)
        speedFines = {
            {fine = 25, maxSpeed = 10 },
            {fine = 50, maxSpeed = 30},
            {fine = 250, maxSpeed = 80},
            {fine = 500, maxSpeed = 180},
        }
    }
}
