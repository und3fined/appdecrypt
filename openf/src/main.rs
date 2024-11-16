// Copyright (c) 2024 und3fy.dev. All rights reserved.
// Created by und3fined <me@und3fy.dev> on 2024 Nov 16.
//
use std::{process, sync::LazyLock};

use clap::Parser;
use frida::{Frida, SpawnOptions};

static FRIDA: LazyLock<Frida> = LazyLock::new(|| unsafe { Frida::obtain() });

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Args {
    /// The bundle identifier of the target app. Example: com.apple.mobilesafari
    bundle_id: String,

    /// The remote port to connect.
    #[arg(short, long, default_value = "1337")]
    remote: Option<String>,
}

fn main() {
    let dm = frida::DeviceManager::obtain(&FRIDA);
    let mut device = dm.get_local_device().unwrap(); // default to local device
    let cli = Args::parse();

    if let Some(remote) = cli.remote {
        let host = format!("127.0.0.1:{}", remote);
        device = dm.get_remote_device(host.as_str()).unwrap(); // switch to remote device
    }

    let spawn_opts = SpawnOptions::new();
    let bundle_id = cli.bundle_id.clone();

    let _pid = device.spawn(bundle_id.as_str(), &spawn_opts).unwrap();
    process::exit(0);
}
