`timescale 1ns/1ps
module queue_equiv_cell #(parameter L=8,D=64,A=6)(output reg done=0);
reg clk=0,rst=0,pop=0;always #5 clk=~clk;
reg[L-1:0]push=0;reg[L*19-1:0]data=0;
wire[18:0]a,b;wire ea,eb,fa,fb,oa,ob;
event_queue_multi #(.LANES(L),.DEPTH(D),.AW(A))d(.clk(clk),.rst_n(rst),.push(push),.data(data),.pop(pop),.head(a),.empty(ea),.full(fa),.overflow(oa));
ap03_event_queue_multi #(.LANES(L),.DEPTH(D),.AW(A))refd(.clk(clk),.rst_n(rst),.push(push),.data(data),.pop(pop),.head(b),.empty(eb),.full(fb),.overflow(ob));
reg[31:0]rng=32'h86720a31;integer n,k;
task check;begin
 if(ea!==eb || fa!==fb || oa!==ob || d.count!==refd.count || d.wr!==refd.wr || d.rd!==refd.rd || (!ea && a!==b))$fatal(1,"queue mismatch L%0d step%0d",L,n);
end endtask
initial begin
 #20;rst=1;
 for(n=0;n<20000;n=n+1)begin
  @(negedge clk);check;
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  case(n%100)
   0,1,2,3,4:begin push={L{1'b1}};pop=0;end
   5,6,7,8,9:begin push=0;pop=1;end
   default:begin push=(n%3==0)?rng[L-1:0]:0;pop=rng[16];end
  endcase
  for(k=0;k<L;k=k+1)data[k*19+:19]=(n*L+k)&19'h7ffff;
  if(n%997==0)begin rst=0;#1;check;@(negedge clk);rst=1;end
 end
 push=0;pop=1;repeat(D+2)begin @(negedge clk);check;end
 $display("PASS AP03 queue cycle-equivalence lanes%0d depth%0d,20k randomized full/pop/push/wrap/overflow/reset cases",L,D);done=1;
end
endmodule
module queue_equiv;
wire a,b,c;
queue_equiv_cell d0(a);
queue_equiv_cell #(.L(4),.D(8),.A(3))d1(b);
queue_equiv_cell #(.L(2),.D(4),.A(2))d2(c);
initial begin wait(a&&b&&c);$finish;end
endmodule
