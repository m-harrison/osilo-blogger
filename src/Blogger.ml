open Osilo
open Core.Std
open Core.Std.Unix

exception Cannot_find_home
exception Could_not_write_config of int
exception Decoding_failed of string

let home = Sys.getenv "HOME" |> 
  begin function
  | Some h -> h
  | None   -> raise Cannot_find_home
  end

let dir  = (Printf.sprintf "%s/.osilo-blogger" home)

let string_member s j = 
  match Yojson.Basic.Util.member s j with
  | `String m -> m
  | _         -> raise (Decoding_failed s)

let read_config () = 
  let file = openfile ~mode:[O_RDONLY] (Printf.sprintf "%s/config.json" dir) in
  let buf = "" in
  read file ~buf;
  let j = Yojson.Basic.from_string buf in
  let p = (string_member "peer" j |> Peer.create          ) in
  let k = (string_member "key" j  |> Coding.decode_cstruct) in
  (close file); (p,k)

let init ~peer ~key =
  mkdir ~perm:0o700 dir;
  let buf  = Yojson.Basic.to_string (`Assoc [("peer", `String (Peer.host peer)); ("key", `String key)]) in
  let file = openfile ~perm:0o600 ~mode:[O_WRONLY;O_CREAT] (Printf.sprintf "%s/config.json" dir) in
  single_write file ~buf |> fun _ -> (close file)

open Osilo.Auth
open Lwt.Infix

let invite ~peer =
  let my_peer,key = read_config () in 
  let plaintext = (`Assoc [("R", `String "posts")]) |> Yojson.Basic.to_string |> Cstruct.of_string in
  let c,i = Cryptography.CS.encrypt' ~key ~plaintext in
  let body = Coding.encode_client_message ~ciphertext:c ~iv:i in
  let path = Printf.sprintf "/client/permit/%s/blogger" (Peer.host peer) in
  Http_client.post ~peer:my_peer ~path ~body
  >|= (fun (c,_) -> 
    if c=204 
    then (Printf.printf "Peer %s has successfully been permitted to read the blog."       (Peer.host peer)) 
    else (Printf.printf "There was a problem giving peer %s permission to read the blog." (Peer.host peer)))

module Cli = struct 
  let init =
    Command.basic
      ~summary:"Initialises a blogger client for the local user."
      Command.Spec.(
        empty
        +> flag "-p" (required string) ~doc:" Hostname of peer to blog from."
        +> flag "-k" (required string) ~doc:" Secret key to share with peer."
      )
      (fun p k () -> init ~peer:(Peer.create p) ~key:k)

  let invite =
    Command.basic
      ~summary:"Invites another peer to read this blog."
      Command.Spec.(
        empty
        +> flag "-p" (required string) ~doc:" Hostname of peer to invite."
      )
      (fun p () -> Lwt_main.run (invite ~peer:(Peer.create p)))

  let commands = 
    Command.group 
      ~summary:"CLI for the osilo blogger."
      [("init",init);("invite",invite)]
end

let () = 
  Command.run
    ~version:"0.1"
    ~build_info:"osilo-blogger"
    Cli.commands
    