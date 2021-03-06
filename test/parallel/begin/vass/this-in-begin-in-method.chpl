// Checks that heap allocation works.

record RR {
  var xx: int;
  proc modify(ee: int) {
    begin {
      this.xx = ee;
    }
  }
}

var rr = new RR();
rr.modify(151515);

if rr.xx != 123123 then writeln("OK");
