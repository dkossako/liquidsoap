(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2010 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)

(** VU meter. *)

open Source

let screen_width = 80
let rms_max = -5.
let rms_min = -25.

let vol n v =
  let v = Audio.dB_of_lin v in
  let ans = ref "" in
  let barwidth = screen_width / n - 7 in
  let barlen = int_of_float (float barwidth *. min 1. (max 0. ((v -. rms_min) /. (rms_max -. rms_min)))) in
    for i = 0 to barlen - 1 do ans := !ans ^ "=" done;
    for i = 0 to barwidth - barlen - 1 do ans := !ans ^ "." done;
    Printf.sprintf "% 5.1f %s" v !ans

class vumeter ~kind source scroll =
object
  inherit operator kind [source] as super

  method stype = source#stype
  method is_ready = source#is_ready
  method remaining = source#remaining
  method abort_track = source#abort_track

  method private get_frame buf =
    let offset = AFrame.position buf in
    source#get buf;
    let rms = AFrame.rms buf offset (AFrame.position buf - offset) in
    let channels = Array.length rms in
    let vol = Array.map (vol channels) rms in
    let vol = Array.fold_left (fun ans s -> ans ^ "  " ^ s) "" vol in
    let vol =
      if channels = 0 then "vumeter: no audio channel!" else
        String.sub vol 2 (String.length vol - 2) in
      if scroll then
        Printf.printf "%s\n%!" vol
      else
        Printf.printf "\r%s%!" vol
end

class rms ~kind source =
object (self)
  inherit operator kind [source] as super

  method stype = source#stype
  method is_ready = source#is_ready
  method remaining = source#remaining
  method abort_track = source#abort_track

  val mutable volume = 0.

  val m = Mutex.create ()

  initializer
  let rms _ =
    Mutex.lock m;
    let ans = string_of_float volume in
    Mutex.unlock m;
    ans
  in
  ns_kind <- "rms";
  self#register_command "rms" ~descr:"Retrieve the current RMS volume of the source." rms

  method private get_frame buf =
    let offset = AFrame.position buf in
    source#get buf;
    let rms = AFrame.rms buf offset (AFrame.position buf - offset) in
    let channels = Array.length rms in
    Mutex.lock m;
    volume <- 0.;
    for i = 0 to channels - 1 do
      volume <- volume +. rms.(i)
    done;
    volume <- volume /. (float channels);
    Mutex.unlock m
end

let () =
  let k = Lang.kind_type_of_kind_format ~fresh:1 Lang.any_fixed in
  Lang.add_operator "vumeter"
    [ "scroll", Lang.bool_t, Some (Lang.bool false), Some "Scroll.";
      "", Lang.source_t k, None, None ]
    ~kind:(Lang.Unconstrained k)
    ~category:Lang.Visualization
    ~descr:"VU meter (display the volume)."
    (fun p kind ->
       let f v = List.assoc v p in
       let scroll, src =
         Lang.to_bool (f "scroll"),
         Lang.to_source (f "")
       in
         new vumeter ~kind src scroll);
  Lang.add_operator "rms"
    [ "", Lang.source_t k, None, None ]
    ~kind:(Lang.Unconstrained k)
    ~category:Lang.Visualization
    ~descr:"Add a telnet rms command to retrieve the current RMS volume of the source."
    (fun p kind ->
       let f v = List.assoc v p in
       let src =
         Lang.to_source (f "")
       in
         new rms ~kind src)
