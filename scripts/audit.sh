#! /usr/bin/env sh

AUDIT_KEY=$1          

if [ -z "$AUDIT_KEY" ]; then
  echo "You must specify an audit key!"
  exit 1
fi

sudo ausearch -ts today -k $AUDIT_KEY 2> /dev/null | awk '
      /type=PATH.*nametype=CREATE/ {
          # Extract the created file
          match($0, /name="([^"]+)"/, arr);
          created_file = arr[1];

          # Extract the mode (permissions) of the file
          match($0, /mode=([0-9]+)/, mode_arr);
          file_mode = mode_arr[1];
      }
      /type=SYSCALL/ {
          # Extract the program (exe) and command (comm) that created the file
          match($0, /exe="([^"]+)"/, exe_arr);
          match($0, /comm="([^"]+)"/, comm_arr);
          program = exe_arr[1];
          comm = comm_arr[1];

          # Extract the UID of the user who created the file
          match($0, /uid=([0-9]+)/, uid_arr);
          uid = uid_arr[1];

          # Use the UID to get the corresponding username
          if (uid) {
              username = strftime("%s", uid);
              username_cmd = "getent passwd " uid " | cut -d: -f1";
              username_cmd | getline username;
              close(username_cmd);
          }

          # if (created_file) {
          #     print "Created File: " created_file;
          #     print "File Mode: " file_mode;
          #     print "Program: " program;
          #     print "Command: " comm;
          #     print "User: " username;
          #     print "----";
          #     created_file = "";  # Reset for the next record
          #     file_mode = "";     # Reset for the next record
          #     username = "";      # Reset for the next record
          # }

          if (created_file) {
            printf "%-40s | %-20s | %-20s\n", created_file, comm, program
                       
            created_file = "";  # Reset for the next record
            file_mode = "";     # Reset for the next record
            username = "";      # Reset for the next record
          }
      }
  '
