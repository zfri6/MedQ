// Stateless identity lookup; no queue/control state. IDs 0..29 match patients.json.
function [5:0] patient_id;
 input room,is_return;input [7:0] ticket;
 begin
  patient_id=6'd63;
  if(is_return && ticket>=8'h01 && ticket<=8'h05)
   patient_id=(room ? 6'd15 : 6'd0)+{2'd0,ticket[3:0]}-6'd1;
  else if(!is_return && ticket>=8'h01 && ticket<=8'h09)
   patient_id=(room ? 6'd20 : 6'd5)+{2'd0,ticket[3:0]}-6'd1;
  else if(!is_return && ticket==8'h10)patient_id=room ? 6'd29 : 6'd14;
 end
endfunction
