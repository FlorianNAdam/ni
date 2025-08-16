use resolve_path::PathResolveExt;

use std::{
    path::{Path, PathBuf},
    process::Command,
};

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "ni")]
#[command(about = "A small nix convenience wrapper", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Rebuilds the Nix environment
    Rebuild {
        /// Specify the flake path to rebuild
        #[arg(long, env = "NIXOS_CONFIG")]
        path: PathBuf,
        #[arg(long, env = "NIXOS_HOST")]
        host: String,
        #[arg(short, long)]
        label: Option<String>,
        message: String,
    },
    /// Updates the Nix environment
    Update {
        /// Specify the flake path to update
        #[arg(long, env = "NIXOS_CONFIG")]
        path: PathBuf,
        #[arg(long, env = "NIXOS_HOST")]
        host: String,
        input: Option<String>,
    },
    /// Syncs the Nix environment with the Repo
    Sync {
        /// Specify the flake path to update
        #[arg(long, env = "NIXOS_CONFIG")]
        path: PathBuf,
        #[arg(long, env = "NIXOS_HOST")]
        host: String,
    },
    /// Test the Nix environment
    Test {
        /// Specify the flake path to test
        #[arg(long, env = "NIXOS_CONFIG")]
        path: PathBuf,
        #[arg(long, env = "NIXOS_HOST")]
        host: String,
    },
    /// Cleans up the Nix environment
    Clean,
    /// Audits the Nix environment for issues
    Audit { key: String },
}

fn main() {
    let cli = Cli::parse();

    match &cli.command {
        Commands::Rebuild {
            path,
            host,
            label,
            message,
        } => {
            rebuild(path, host, label.as_deref(), message).unwrap();
        }
        Commands::Update { path, host, input } => {
            update(path, host, input.as_deref()).unwrap();
        }
        Commands::Sync { path, host } => {
            sync(path, host).unwrap();
        }
        Commands::Test { path, host } => {
            test(path, host).unwrap();
        }
        Commands::Audit { key } => {
            audit(key).unwrap();
        }
        Commands::Clean {} => clean().unwrap(),
    }
}

fn rebuild(
    nixos_path: &Path,
    host: &str,
    label: Option<&str>,
    message: &str,
) -> anyhow::Result<()> {
    let nixos_path = nixos_path.resolve();
    let label = label.unwrap_or(message);
    let sanitized_label = sanitize_label(label);

    println!("path: {:?}", nixos_path);
    println!("host: {:?}", host);
    println!("message: {:?}", message);
    println!("label: {:?}", sanitized_label);

    let mut command = script_command("rebuild");
    command
        .arg(nixos_path.as_ref())
        .arg(host)
        .arg(message)
        .arg(sanitized_label)
        .status()?;

    Ok(())
}

fn update(nixos_path: &Path, host: &str, input: Option<&str>) -> anyhow::Result<()> {
    let nixos_path = nixos_path.resolve();

    let mut command = script_command("update");
    command.arg(nixos_path.as_ref());
    if let Some(input) = input {
        command.arg(input);
    }
    command.status()?;

    let message = if let Some(input) = input {
        format!("update {}", input)
    } else {
        "update".to_string()
    };

    rebuild(nixos_path.as_ref(), host, None, &message)?;

    Ok(())
}

fn sync(nixos_path: &Path, host: &str) -> anyhow::Result<()> {
    let nixos_path = nixos_path.resolve();

    let mut command = script_command("sync");
    command.arg(nixos_path.as_ref()).arg(host).status()?;

    Ok(())
}

fn test(nixos_path: &Path, host: &str) -> anyhow::Result<()> {
    let nixos_path = nixos_path.resolve();

    let mut command = script_command("test");
    command.arg(nixos_path.as_ref()).arg(host).status()?;

    Ok(())
}

fn clean() -> anyhow::Result<()> {
    let mut command = script_command("clean");
    command.status()?;

    Ok(())
}

fn audit(key: &str) -> anyhow::Result<()> {
    let mut command = script_command("audit");
    command.arg(key).status()?;

    Ok(())
}

fn sanitize_label(input: &str) -> String {
    input
        .chars()
        .filter_map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | ':' | '_' | '.' | '-' => Some(c),
            ' ' => Some('_'),
            _ => None,
        })
        .collect()
}

fn script_command(name: &str) -> Command {
    let script_path = std::option_env!("MY_SCRIPT_PATH")
        .map(PathBuf::from)
        .unwrap_or(PathBuf::from(
            PathBuf::from(std::env!("CARGO_MANIFEST_DIR")).join("scripts"),
        ));

    let script_path = script_path.join(name).with_extension("sh");

    Command::new(script_path)
}
