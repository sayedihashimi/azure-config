namespace MyWebApi.Controllers {
    using Shared;
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Net;
    using System.Net.Http;
    using System.Web.Http;

    public class OrdersController : ApiController {
        // GET api/orders
        public IEnumerable<string> Get() {
            return new string[] { "value1", "value2" };
        }

        // GET api/orders/5
        public string Get(int id) {
            return "value";
        }

        // POST api/orders
        public void Post([FromBody]string value) {
        }

        // PUT api/orders/5
        public void Put([FromBody]Order order) {
            // insert the order here


            string name = order.Name;

        }

        // DELETE api/orders/5
        public void Delete(int id) {
        }
    }
}
